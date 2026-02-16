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

  // Atomic social field updates (for offline player mutations)
  router.patch("/:id/social", async (req, res) => {
    try {
      const playerId = req.params.id;
      const ops = req.body;
      if (!ops || typeof ops !== "object") {
        return res.status(400).json({ error: "Request body must be an object of operations" });
      }

      const updateDoc: Record<string, any> = {};
      const pullDoc: Record<string, any> = {};

      // $addToSet operations
      if (ops.add_friend && typeof ops.add_friend === "string") {
        updateDoc["$addToSet"] = updateDoc["$addToSet"] || {};
        updateDoc["$addToSet"]["social.friends"] = ops.add_friend;
      }
      if (ops.add_blocked && typeof ops.add_blocked === "string") {
        updateDoc["$addToSet"] = updateDoc["$addToSet"] || {};
        updateDoc["$addToSet"]["social.blocked"] = ops.add_blocked;
      }
      if (ops.add_incoming_request && typeof ops.add_incoming_request === "object") {
        updateDoc["$addToSet"] = updateDoc["$addToSet"] || {};
        updateDoc["$addToSet"]["social.incoming_requests"] = ops.add_incoming_request;
      }
      if (ops.add_outgoing_request && typeof ops.add_outgoing_request === "object") {
        updateDoc["$addToSet"] = updateDoc["$addToSet"] || {};
        updateDoc["$addToSet"]["social.outgoing_requests"] = ops.add_outgoing_request;
      }

      // $pull operations
      if (ops.remove_friend && typeof ops.remove_friend === "string") {
        pullDoc["social.friends"] = ops.remove_friend;
      }
      if (ops.remove_blocked && typeof ops.remove_blocked === "string") {
        pullDoc["social.blocked"] = ops.remove_blocked;
      }
      if (ops.remove_incoming_request_from && typeof ops.remove_incoming_request_from === "string") {
        pullDoc["social.incoming_requests"] = { from_id: ops.remove_incoming_request_from };
      }
      if (ops.remove_outgoing_request_to && typeof ops.remove_outgoing_request_to === "string") {
        pullDoc["social.outgoing_requests"] = { to_id: ops.remove_outgoing_request_to };
      }

      // Build the final update pipeline — MongoDB doesn't allow $addToSet and $pull in the same update
      // so we run them sequentially if both are present
      const player = await col.findOne({ player_id: playerId });
      if (!player) {
        return res.status(404).json({ error: "Player not found" });
      }

      // Ensure social sub-document exists
      if (!player.social) {
        await col.updateOne(
          { player_id: playerId },
          { $set: { social: { friends: [], blocked: [], incoming_requests: [], outgoing_requests: [] } } }
        );
      }

      if (Object.keys(updateDoc).length > 0) {
        await col.updateOne({ player_id: playerId }, updateDoc);
      }
      if (Object.keys(pullDoc).length > 0) {
        await col.updateOne({ player_id: playerId }, { $pull: pullDoc });
      }

      res.json({ ok: true });
    } catch (err) {
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
