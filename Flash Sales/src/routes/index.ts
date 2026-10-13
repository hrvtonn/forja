import { Router } from "express";
import { CheckoutController } from "../controllers/CheckoutController";
import { ExportController } from "../controllers/ExportController";
import { HealthController } from "../controllers/HealthController";
import { metricsController } from "../middlewares/metricsMiddleware";

const router = Router();
const checkoutController = new CheckoutController();
const exportController = new ExportController();
const healthController = new HealthController();

router.post("/checkout", (req, res, next) => checkoutController.handle(req, res).catch(next));
router.post("/tickets/export", (req, res, next) => exportController.handle(req, res).catch(next));
router.get("/health", (req, res, next) => healthController.live(req, res).catch(next));
router.get("/ready", (req, res, next) => healthController.ready(req, res).catch(next));
router.get("/metrics", metricsController);

export { router };
