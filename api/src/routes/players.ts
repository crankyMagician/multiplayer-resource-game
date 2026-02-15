import { Router } from "express";
import { type Db } from "mongodb";
import crypto from "node:crypto";

export function createPlayerRoutes(db: Db): Router {
  const router = Router();
  const col = db.collection("players");

  // Load player by display name
  router.get("/by-name/:name", async (req, res) => {
    try {
      const doc = await col.findOne({ player_name: req.params.name });
      res.json(doc || {});
    } catch (err) {
      res.status(500).json({ error: String(err) });
    }
  });

  // Check if a player name exists (for join validation)
  router.get("/by-name/:name/exists", async (req, res) => {
    try {
      const count = await col.countDocuments({ player_name: req.params.name }, { limit: 1 });
      res.json({ exists: count > 0 });
    } catch (err) {
      res.status(500).json({ error: String(err) });
    }
  });

  // Load player by UUID
  router.get("/:id", async (req, res) => {
    try {
      const doc = await col.findOne({ player_id: req.params.id });
      if (!doc) {
        return res.status(404).json({ error: "Player not found" });
      }
      res.json(doc);
    } catch (err) {
      res.status(500).json({ error: String(err) });
    }
  });

  // Create new player (generates UUID)
  router.post("/", async (req, res) => {
    try {
      const data = req.body;
      if (!data.player_name || typeof data.player_name !== "string") {
        return res.status(400).json({ error: "player_name required" });
      }
      const playerId = crypto.randomUUID();
      const doc = { ...data, player_id: playerId };
      // Use player_id as MongoDB _id for efficient lookups
      await col.insertOne({ _id: playerId as any, ...doc });
      res.status(201).json(doc);
    } catch (err: any) {
      if (err?.code === 11000) {
        // Duplicate key — name already taken
        return res.status(409).json({ error: "Player name already exists" });
      }
      res.status(500).json({ error: String(err) });
    }
  });

  // Upsert player by UUID
  router.put("/:id", async (req, res) => {
    try {
      const data = req.body;
      const playerId = req.params.id;
      const result = await col.replaceOne(
        { player_id: playerId },
        { ...data, player_id: playerId },
        { upsert: true }
      );
      res.json({ ok: true, upserted: result.upsertedCount > 0 });
    } catch (err: any) {
      if (err?.code === 11000) {
        return res.status(409).json({ error: "Player name conflict" });
      }
      res.status(500).json({ error: String(err) });
    }
  });

  // Delete player by UUID
  router.delete("/:id", async (req, res) => {
    try {
      const result = await col.deleteOne({ player_id: req.params.id });
      if (result.deletedCount === 0) {
        return res.status(404).json({ error: "Player not found" });
      }
      res.json({ ok: true });
    } catch (err) {
      res.status(500).json({ error: String(err) });
    }
  });

  return router;
}
