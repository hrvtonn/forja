import { Router } from "express";
import { ContractController } from "../controllers/ContractController";
import { HealthController } from "../controllers/HealthController";
import { metricsController } from "../middlewares/metricsMiddleware";

const router = Router();
const contractController = new ContractController();
const healthController = new HealthController();

router.post("/contracts", (req, res, next) => contractController.handle(req, res).catch(next));
router.get("/health", (req, res, next) => healthController.live(req, res).catch(next));
router.get("/ready", (req, res, next) => healthController.ready(req, res).catch(next));
router.get("/metrics", metricsController);

export { router };
