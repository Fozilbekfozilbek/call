let io = null;

function init(server) {
  const { Server } = require('socket.io');
  io = new Server(server, {
    cors: { origin: '*' },
  });

  io.on('connection', (socket) => {
    // Client identifies itself right after connecting so we can target
    // events at the right admin/worker rooms.
    // Expected payload: { role: 'admin' | 'worker', userId: number }
    socket.on('identify', ({ role, userId }) => {
      if (role === 'admin') {
        socket.join('admins');
      } else if (role === 'worker' && userId) {
        socket.join(`worker_${userId}`);
      }
    });

    socket.on('disconnect', () => {});
  });

  return io;
}

function getIO() {
  if (!io) {
    throw new Error('Socket.IO not initialized. Call init(server) first.');
  }
  return io;
}

module.exports = { init, getIO };
