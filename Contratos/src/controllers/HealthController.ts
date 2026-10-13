import { Request, Response } from "express";
import { AppDataSource } from "../config/database";
import { redis } from "../config/redis";

export class HealthController {
  // Liveness: o processo está ativo e o event loop responde
  async live(req: Request, res: Response): Promise<Response> {
    return res.status(200).json({ status: "ok" });
  }

  // Readiness: só recebe tráfego quando Postgres e Redis estão acessíveis
  async ready(req: Request, res: Response): Promise<Response> {
    try {
      await AppDataSource.query("SELECT 1");
      await redis.ping();
      return res.status(200).json({ status: "ready" });
    } catch (error: any) {
      return res.status(503).json({ status: "unavailable", details: error.message });
    }
  }
}
