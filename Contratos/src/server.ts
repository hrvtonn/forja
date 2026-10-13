import { app } from "./app";
import { AppDataSource } from "./config/database";
import { redis } from "./config/redis";

const PORT = process.env.PORT || 3000;
const SHUTDOWN_TIMEOUT_MS = 10000;
// Maior que o idle timeout dos proxies (Traefik/Nginx/LBs ~60s): evita que o Node feche
// uma conexão keep-alive no mesmo instante em que o proxy a reutiliza (ECONNRESET)
const KEEP_ALIVE_TIMEOUT_MS = 65000;

AppDataSource.initialize()
  .then(() => {
    console.log("Data Source has been initialized!");
    const server = app.listen(PORT, () => {
      console.log(`Server is running on port ${PORT}`);
    });
    server.keepAliveTimeout = KEEP_ALIVE_TIMEOUT_MS;
    server.headersTimeout = KEEP_ALIVE_TIMEOUT_MS + 1000;

    // Encerramento gracioso: o orquestrador (Docker/Kubernetes) envia SIGTERM antes de
    // remover o container; terminamos as requisições em andamento e fechamos as conexões.
    const shutdown = (signal: string) => {
      console.log(`${signal} received, shutting down gracefully...`);
      setTimeout(() => process.exit(1), SHUTDOWN_TIMEOUT_MS).unref();

      server.close(async () => {
        await AppDataSource.destroy().catch(() => undefined);
        await redis.quit().catch(() => undefined);
        process.exit(0);
      });
    };

    process.on("SIGTERM", () => shutdown("SIGTERM"));
    process.on("SIGINT", () => shutdown("SIGINT"));
  })
  .catch((err) => {
    console.error("Error during Data Source initialization:", err);
    // Falha explícita para que o orquestrador reinicie o container
    process.exit(1);
  });
