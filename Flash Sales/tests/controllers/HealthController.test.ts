import { HealthController } from "../../src/controllers/HealthController";
import { redis } from "../../src/config/redis";
import { AppDataSource } from "../../src/config/database";

jest.mock("../../src/config/redis", () => ({
  redis: {
    ping: jest.fn(),
  },
}));

jest.mock("../../src/config/database", () => ({
  AppDataSource: {
    query: jest.fn(),
  },
}));

function mockResponse(): any {
  const res: any = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

describe("HealthController", () => {
  const healthController = new HealthController();

  it("should report liveness without touching dependencies", async () => {
    const res = mockResponse();

    await healthController.live({} as any, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(AppDataSource.query).not.toHaveBeenCalled();
    expect(redis.ping).not.toHaveBeenCalled();
  });

  it("should be ready when database and redis respond", async () => {
    (AppDataSource.query as jest.Mock).mockResolvedValue([{ "?column?": 1 }]);
    (redis.ping as jest.Mock).mockResolvedValue("PONG");
    const res = mockResponse();

    await healthController.ready({} as any, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith({ status: "ready" });
  });

  it("should return 503 when a dependency is unavailable", async () => {
    (AppDataSource.query as jest.Mock).mockRejectedValue(new Error("connection refused"));
    const res = mockResponse();

    await healthController.ready({} as any, res);

    expect(res.status).toHaveBeenCalledWith(503);
    expect(res.json).toHaveBeenCalledWith({ status: "unavailable", details: "connection refused" });
  });
});
