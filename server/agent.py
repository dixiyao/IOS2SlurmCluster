import socket
import json
import subprocess
import threading
import os
import yaml
from google import genai
from google.genai import types

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)

# Load settings
with open(os.path.join(ROOT_DIR, "settings.yml"), "r") as f:
    settings = yaml.safe_load(f)

# Load prompt library
with open(os.path.join(SCRIPT_DIR, "prompt_library.json"), "r") as f:
    prompts = json.load(f)

API_KEY = settings["api"]["api_key"]
MODEL = settings["api"]["model"]
HOST = settings["agent"]["socket_host"]
PORT = settings["agent"]["socket_port"]
SYSTEM_PROMPT = prompts["default"]

# Google GenAI client
client = genai.Client(api_key=API_KEY)

# Tool declarations
TOOL_DECLARATIONS = types.Tool(function_declarations=[
    {
        "name": "run_command",
        "description": "Execute a shell command on the server and return stdout, stderr, and exit code.",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The shell command to execute"
                }
            },
            "required": ["command"]
        }
    },
    {
        "name": "create_file",
        "description": "Create or overwrite a file at the given path with the given content.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Absolute or relative file path"
                },
                "content": {
                    "type": "string",
                    "description": "File content to write"
                }
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "read_file",
        "description": "Read and return the contents of a file.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Absolute or relative file path"
                }
            },
            "required": ["path"]
        }
    }
])

CONFIG = types.GenerateContentConfig(
    tools=[TOOL_DECLARATIONS],
    system_instruction=SYSTEM_PROMPT,
)


def execute_tool(name, args):
    """Execute a tool call and return the result string."""
    if name == "run_command":
        try:
            result = subprocess.run(
                args["command"], shell=True, capture_output=True, text=True, timeout=120
            )
            output = ""
            if result.stdout:
                output += result.stdout
            if result.stderr:
                output += "\nSTDERR:\n" + result.stderr
            output += f"\n[exit code: {result.returncode}]"
            return output.strip()
        except subprocess.TimeoutExpired:
            return "[error: command timed out after 120s]"
        except Exception as e:
            return f"[error: {e}]"

    elif name == "create_file":
        try:
            path = os.path.expanduser(args["path"])
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
            with open(path, "w") as f:
                f.write(args["content"])
            return f"File created: {path}"
        except Exception as e:
            return f"[error: {e}]"

    elif name == "read_file":
        try:
            path = os.path.expanduser(args["path"])
            with open(path, "r") as f:
                return f.read()
        except Exception as e:
            return f"[error: {e}]"

    return f"[error: unknown tool {name}]"


def process_message(contents):
    """Run the agentic loop: call Gemini, execute tools, repeat until text response."""
    while True:
        response = client.models.generate_content(
            model=MODEL,
            contents=contents,
            config=CONFIG,
        )

        # Append assistant response to conversation
        contents.append(response.candidates[0].content)

        # Check for function calls in response parts
        function_calls = [
            part.function_call
            for part in response.candidates[0].content.parts
            if part.function_call
        ]

        if not function_calls:
            # No tool calls — return text
            return response.text or ""

        # Execute each function call and build response parts
        function_response_parts = []
        for fc in function_calls:
            result = execute_tool(fc.name, dict(fc.args))
            function_response_parts.append(
                types.Part.from_function_response(
                    name=fc.name,
                    response={"result": result},
                )
            )

        # Append tool results as user turn
        contents.append(types.Content(role="user", parts=function_response_parts))


def handle_client(conn, addr):
    """Handle a single client connection."""
    print(f"[+] Client connected: {addr}")
    contents = []
    buffer = ""

    try:
        while True:
            data = conn.recv(4096)
            if not data:
                break

            buffer += data.decode("utf-8")

            # Process complete newline-delimited JSON messages
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                line = line.strip()
                if not line:
                    continue

                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    conn.sendall(json.dumps({"error": "invalid json"}).encode() + b"\n")
                    continue

                user_text = msg.get("content", "")
                if not user_text:
                    continue

                print(f"[>] {addr}: {user_text[:80]}")

                # Add user message
                contents.append(
                    types.Content(role="user", parts=[types.Part(text=user_text)])
                )

                # Process with Gemini agent loop
                try:
                    reply = process_message(contents)
                except Exception as e:
                    reply = f"Agent error: {e}"

                print(f"[<] {addr}: {reply[:80]}")

                # Send response back
                response_json = json.dumps({"content": reply}) + "\n"
                conn.sendall(response_json.encode("utf-8"))

    except ConnectionResetError:
        pass
    finally:
        conn.close()
        print(f"[-] Client disconnected: {addr}")


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(5)
    print(f"Agent listening on {HOST}:{PORT}")
    print("Waiting for connections (use SSH tunnel to connect)...")

    try:
        while True:
            conn, addr = srv.accept()
            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()
    except KeyboardInterrupt:
        print("\nShutting down.")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
