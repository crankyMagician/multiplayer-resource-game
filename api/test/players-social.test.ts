import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import request from "supertest";
import { setupTestDb, teardownTestDb, clearCollections } from "./setup.js";
import type { Express } from "express";
import type { Db } from "mongodb";

let app: Express;
let db: Db;

beforeAll(async () => {
  const ctx = await setupTestDb();
  app = ctx.app;
  db = ctx.db;
});

afterAll(async () => {
  await teardownTestDb();
});

beforeEach(async () => {
  await clearCollections();
});

async function createPlayer(name: string, social?: object) {
  const res = await request(app)
    .post("/api/players")
    .send({ player_name: name, social: social || { friends: [], blocked: [], incoming_requests: [], outgoing_requests: [] } });
  return res.body;
}

describe("PATCH /api/players/:id/social", () => {
  it("returns 404 for non-existent player", async () => {
    const res = await request(app)
      .patch("/api/players/nonexistent/social")
      .send({ add_friend: "some-uuid" });
    expect(res.status).toBe(404);
  });

  it("adds a friend to empty friends list", async () => {
    const player = await createPlayer("Alice");
    const res = await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ add_friend: "friend-uuid" });
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);

    // Verify
    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.friends).toContain("friend-uuid");
  });

  it("removes a friend", async () => {
    const player = await createPlayer("Bob", {
      friends: ["uuid-1", "uuid-2"],
      blocked: [],
      incoming_requests: [],
      outgoing_requests: [],
    });
    const res = await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ remove_friend: "uuid-1" });
    expect(res.status).toBe(200);

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.friends).toEqual(["uuid-2"]);
  });

  it("adds a blocked player", async () => {
    const player = await createPlayer("Carol");
    await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ add_blocked: "blocked-uuid" });

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.blocked).toContain("blocked-uuid");
  });

  it("removes a blocked player", async () => {
    const player = await createPlayer("Dave", {
      friends: [],
      blocked: ["b1", "b2"],
      incoming_requests: [],
      outgoing_requests: [],
    });
    await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ remove_blocked: "b1" });

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.blocked).toEqual(["b2"]);
  });

  it("adds an incoming request", async () => {
    const player = await createPlayer("Eve");
    const reqData = { from_id: "sender-uuid", from_name: "Sender", sent_at: 1000 };
    await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ add_incoming_request: reqData });

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.incoming_requests).toHaveLength(1);
    expect(get.body.social.incoming_requests[0].from_id).toBe("sender-uuid");
  });

  it("removes an incoming request by from_id", async () => {
    const player = await createPlayer("Frank", {
      friends: [],
      blocked: [],
      incoming_requests: [
        { from_id: "a", from_name: "A", sent_at: 1 },
        { from_id: "b", from_name: "B", sent_at: 2 },
      ],
      outgoing_requests: [],
    });
    await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ remove_incoming_request_from: "a" });

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.incoming_requests).toHaveLength(1);
    expect(get.body.social.incoming_requests[0].from_id).toBe("b");
  });

  it("adds an outgoing request", async () => {
    const player = await createPlayer("Grace");
    const reqData = { to_id: "target-uuid", to_name: "Target", sent_at: 2000 };
    await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ add_outgoing_request: reqData });

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.outgoing_requests).toHaveLength(1);
    expect(get.body.social.outgoing_requests[0].to_id).toBe("target-uuid");
  });

  it("removes an outgoing request by to_id", async () => {
    const player = await createPlayer("Heidi", {
      friends: [],
      blocked: [],
      incoming_requests: [],
      outgoing_requests: [
        { to_id: "x", to_name: "X", sent_at: 1 },
        { to_id: "y", to_name: "Y", sent_at: 2 },
      ],
    });
    await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ remove_outgoing_request_to: "x" });

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.outgoing_requests).toHaveLength(1);
    expect(get.body.social.outgoing_requests[0].to_id).toBe("y");
  });

  it("initializes social sub-document if missing", async () => {
    // Create player without social field
    const res = await request(app)
      .post("/api/players")
      .send({ player_name: "NoSocial" });
    const playerId = res.body.player_id;

    await request(app)
      .patch(`/api/players/${playerId}/social`)
      .send({ add_friend: "new-friend" });

    const get = await request(app).get(`/api/players/${playerId}`);
    expect(get.body.social).toBeDefined();
    expect(get.body.social.friends).toContain("new-friend");
  });

  it("handles multiple operations (add friend + remove request)", async () => {
    const player = await createPlayer("Ivan", {
      friends: [],
      blocked: [],
      incoming_requests: [{ from_id: "req-uuid", from_name: "Req", sent_at: 1 }],
      outgoing_requests: [],
    });

    // Add friend and remove the incoming request
    await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({
        add_friend: "req-uuid",
        remove_incoming_request_from: "req-uuid",
      });

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.friends).toContain("req-uuid");
    expect(get.body.social.incoming_requests).toHaveLength(0);
  });

  it("handles empty operations gracefully", async () => {
    const player = await createPlayer("Judy");
    const res = await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({});
    // No operations = no changes, still OK
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it("does not duplicate friends with $addToSet", async () => {
    const player = await createPlayer("Karen", {
      friends: ["existing-friend"],
      blocked: [],
      incoming_requests: [],
      outgoing_requests: [],
    });

    await request(app)
      .patch(`/api/players/${player.player_id}/social`)
      .send({ add_friend: "existing-friend" });

    const get = await request(app).get(`/api/players/${player.player_id}`);
    expect(get.body.social.friends).toEqual(["existing-friend"]);
  });
});
