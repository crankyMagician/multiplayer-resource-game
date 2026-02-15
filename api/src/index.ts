import "dotenv/config";
import express from "express";
import { MongoClient, type Db } from "mongodb";
import { createPlayerRoutes } from "./routes/players.js";
import { createWorldRoutes } from "./routes/world.js";

const PORT = parseInt(process.env.PORT || "3000", 10);
const MONGO_URI = process.env.MONGO_URI || "mongodb://localhost:27017/creature_crafting";

let db: Db;

async function main() {
  // Connect to MongoDB
  const client = new MongoClient(MONGO_URI);
  await client.connect();
  db = client.db();
  console.log(`[API] Connected to MongoDB: ${MONGO_URI}`);

  // Ensure indexes
  await db.collection("players").createIndex({ player_name: 1 }, { unique: true });
  console.log("[API] Ensured unique index on players.player_name");

  const app = express();
  app.use(express.json({ limit: "1mb" }));

  // Health check
  app.get("/health", async (_req, res) => {
    try {
      await db.command({ ping: 1 });
      res.json({ status: "ok", db: "connected" });
    } catch (err) {
      res.status(503).json({ status: "error", db: "disconnected", error: String(err) });
    }
  });

  // Mount routes
  app.use("/api/players", createPlayerRoutes(db));
  app.use("/api/world", createWorldRoutes(db));

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`[API] Listening on port ${PORT}`);
  });
}

main().catch((err) => {
  console.error("[API] Fatal error:", err);
  process.exit(1);
});
