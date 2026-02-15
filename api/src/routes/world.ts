import { Router } from "express";
import { type Db } from "mongodb";

const WORLD_DOC_ID = "world_state";

export function createWorldRoutes(db: Db): Router {
  const router = Router();
  const col = db.collection("world");

  // Load world state
  router.get("/", async (_req, res) => {
    try {
      const doc = await col.findOne({ _id: WORLD_DOC_ID as any });
      if (!doc) {
        return res.json({});
      }
      // Remove MongoDB _id from response
      const { _id, ...data } = doc;
      res.json(data);
    } catch (err) {
      res.status(500).json({ error: String(err) });
    }
  });

  // Upsert world state
  router.put("/", async (req, res) => {
    try {
      const data = req.body;
      await col.replaceOne(
        { _id: WORLD_DOC_ID as any },
        { _id: WORLD_DOC_ID as any, ...data },
        { upsert: true }
      );
      res.json({ ok: true });
    } catch (err) {
      res.status(500).json({ error: String(err) });
    }
  });

  return router;
}
