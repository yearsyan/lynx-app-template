import { WebSocketServer } from 'ws';

const host = process.env.LYNX_WS_HOST ?? '0.0.0.0';
const parsedPort = Number(process.env.LYNX_WS_PORT ?? '8787');
if (!Number.isInteger(parsedPort) || parsedPort < 1 || parsedPort > 65535) {
  throw new Error('LYNX_WS_PORT must be an integer between 1 and 65535');
}

const server = new WebSocketServer({ host, port: parsedPort });

server.on('connection', (socket, request) => {
  console.info(
    `WebSocket connected: ${request.socket.remoteAddress ?? 'unknown'}`,
  );
  socket.on('message', (data, isBinary) => {
    socket.send(data, { binary: isBinary });
  });
  socket.on('error', (error) => {
    console.error(`WebSocket connection failed: ${error.message}`);
  });
});

server.on('listening', () => {
  console.info(`Lynx WebSocket echo server: ws://${host}:${parsedPort}`);
});

server.on('error', (error) => {
  console.error(`WebSocket server failed: ${error.message}`);
  process.exitCode = 1;
});

function shutdown() {
  server.close(() => process.exit(0));
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
