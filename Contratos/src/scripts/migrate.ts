import { AppDataSource } from "../config/database";

// Identificador arbitrário do lock de migração no Postgres
const MIGRATION_LOCK_ID = 727274;

/**
 * Sincroniza o schema do banco uma única vez antes do deploy da aplicação.
 * Executado como initContainer (Kubernetes) ou serviço one-shot (Docker Compose),
 * permitindo que as réplicas da API rodem com DB_SYNCHRONIZE=false.
 * O advisory lock impede que execuções concorrentes alterem o schema ao mesmo tempo.
 */
async function migrate(): Promise<void> {
  await AppDataSource.initialize();
  const queryRunner = AppDataSource.createQueryRunner();
  await queryRunner.connect();

  try {
    await queryRunner.query("SELECT pg_advisory_lock($1)", [MIGRATION_LOCK_ID]);
    console.log("Migration lock acquired, synchronizing schema...");
    await AppDataSource.synchronize();
    console.log("Schema synchronized successfully");
  } finally {
    await queryRunner.query("SELECT pg_advisory_unlock($1)", [MIGRATION_LOCK_ID]);
    await queryRunner.release();
    await AppDataSource.destroy();
  }
}

migrate()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Migration failed:", err);
    process.exit(1);
  });
