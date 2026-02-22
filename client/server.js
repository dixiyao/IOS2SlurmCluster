const express = require("express");
const http = require("http");
const { WebSocketServer } = require("ws");
const { Client } = require("ssh2");
const net = require("net");
const fs = require("fs");
const path = require("path");
const YAML = require("yaml");

// Load settings
const settingsPath = path.join(__dirname, "..", "settings.yml");
const settings = YAML.parse(fs.readFileSync(settingsPath, "utf8"));

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(express.static(path.join(__dirname, "public")));

wss.on("connection", (ws) => {
  console.log("[+] Browser connected");

  let sshClient = null;
  let agentSocket = null;
  let agentBuffer = "";

  ws.on("message", (raw) => {
    const msg = JSON.parse(raw.toString());

    // Connect: establish SSH tunnel to agent
    if (msg.type === "connect") {
      sshClient = new Client();

      sshClient.on("ready", () => {
        console.log("[+] SSH connected");

        // Forward local connection to agent socket on remote server
        const remoteHost = settings.agent.socket_host;
        const remotePort = settings.agent.socket_port;

        sshClient.forwardOut("127.0.0.1", 0, remoteHost, remotePort, (err, stream) => {
          if (err) {
            ws.send(JSON.stringify({ type: "error", content: `Tunnel failed: ${err.message}` }));
            return;
          }

          agentSocket = stream;
          ws.send(JSON.stringify({ type: "connected" }));
          console.log("[+] Tunnel to agent established");

          // Receive data from agent
          stream.on("data", (data) => {
            agentBuffer += data.toString("utf8");

            while (agentBuffer.includes("\n")) {
              const idx = agentBuffer.indexOf("\n");
              const line = agentBuffer.slice(0, idx).trim();
              agentBuffer = agentBuffer.slice(idx + 1);

              if (!line) continue;
              try {
                const agentMsg = JSON.parse(line);
                ws.send(JSON.stringify({ type: "response", content: agentMsg.content }));
              } catch {
                ws.send(JSON.stringify({ type: "response", content: line }));
              }
            }
          });

          stream.on("close", () => {
            ws.send(JSON.stringify({ type: "disconnected" }));
            console.log("[-] Agent stream closed");
          });
        });
      });

      sshClient.on("error", (err) => {
        ws.send(JSON.stringify({ type: "error", content: `SSH error: ${err.message}` }));
        console.error("SSH error:", err.message);
      });

      sshClient.connect({
        host: settings.ssh.host,
        port: settings.ssh.port,
        username: settings.ssh.username,
        password: settings.ssh.password,
      });
    }

    // Chat message: forward to agent
    if (msg.type === "message" && agentSocket) {
      const payload = JSON.stringify({ content: msg.content }) + "\n";
      agentSocket.write(payload);
    }

    // Disconnect
    if (msg.type === "disconnect") {
      if (agentSocket) agentSocket.end();
      if (sshClient) sshClient.end();
      agentSocket = null;
      sshClient = null;
    }
  });

  ws.on("close", () => {
    if (agentSocket) agentSocket.end();
    if (sshClient) sshClient.end();
    console.log("[-] Browser disconnected");
  });
});

const PORT = 3000;
server.listen(PORT, () => {
  console.log(`Client running at http://localhost:${PORT}`);
});
