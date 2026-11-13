import { loadConfig } from './config.mjs';
import { createServer } from './server.mjs';
const config = loadConfig({ PORTAL_PREVIEW: 'true', PORT: process.env.PORT || '8080' });
createServer(config).listen(config.port, config.host, () => console.log(`Corvia preview: http://${config.host}:${config.port} (checkout disabled)`));
