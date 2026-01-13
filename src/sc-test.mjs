import * as client from 'socketcluster-client';

const socket = client.create({
  // hostname: 'api.dev.edugolo.be',
  host: '10.21.10.80:8000',
  // hostname: 'localhost',
  // port: 443,
  // port: 8000,
  // secure: true,
  // Only necessary during debug if using a self-signed certificate
  // wsOptions: { rejectUnauthorized: false },
  autoReconnectOptions: {
    initialDelay: 1000, // in milliseconds
    maxDelay: 2000, // in milliseconds
  },
});
(async () => {
  for await (const event of socket.listener('connect')) {
    console.log(`Connected to server with socket id ${socket.id}`);
    console.log(`Authenticated?: ${event.isAuthenticated}`);

    if (!event.isAuthenticated) {
      // router.push({ name: 'login'})
      // window.location.replace(`http://localhost:9000`);
    }
    (async () => {
      let channel = socket.subscribe('foo');
      for await (let data of channel) {
        console.log(data);
        actions[data.action](data.payload);
      }
    })();
  }
})();
(async () => {
  for await (const event of socket.listener('disconnect')) {
    console.log('Disconnected from server');
  }
})();
(async () => {
  for await (const event of socket.listener('authStateChange')) {
    console.log(`authStateChange ${socket.id}`);
    // if (event.newAuthState === 'authenticated') {
    //   router.push({ name: 'chat' });
    // } else {
    //   router.push({ name: 'login' });
    // }
  }
})();
(async () => {
  for await (const event of socket.listener('error')) {
    console.log(event.error);
  }
})();
