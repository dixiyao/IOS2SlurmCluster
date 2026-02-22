import socket
import json
import subprocess
import threading
import queue
import os
import yaml
import anthropic

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

client = anthropic.Anthropic(api_key=API_KEY)

# Tool definitions for Claude
TOOLS = [
    {
        "name": "run_command",
        "description": "Execute a shell command on the server and return stdout, stderr, and exit code.",
        "input_schema": {
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
        "input_schema": {
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
        "input_schema": {
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
]


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


def process_message(conversation):
    """Run the agentic loop: call Claude, execute tools, repeat until text response."""
    while True:
        response = client.messages.create(
            model=MODEL,
            max_tokens=4096,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=conversation,
        )

        # Collect assistant content blocks
        assistant_content = response.content
        conversation.append({"role": "assistant", "content": assistant_content})

        # Check if we need to execute tool calls
        tool_uses = [b for b in assistant_content if b.type == "tool_use"]
        if not tool_uses:
            # No tool calls — extract text and return
            text_parts = [b.text for b in assistant_content if b.type == "text"]
            return "\n".join(text_parts)

        # Execute each tool call and build tool results
        tool_results = []
        for tool_use in tool_uses:
            result = execute_tool(tool_use.name, tool_use.input)
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tool_use.id,
                "content": result,
            })

        conversation.append({"role": "user", "content": tool_results})


def handle_client(conn, addr):
    """Handle a single client connection."""
    print(f"[+] Client connected: {addr}")
    conversation = []
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

                # Add user message to conversation
                conversation.append({"role": "user", "content": user_text})

                # Process with Claude agent loop
                try:
                    reply = process_message(conversation)
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