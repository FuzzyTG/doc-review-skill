// GET /api/annotations - list all annotations with comments
// POST /api/annotations - create annotation + first comment

export async function onRequestGet(context) {
  const db = context.env.DB;
  const anns = await db.prepare('SELECT * FROM annotations ORDER BY created_at').all();
  const result = [];
  for (const ann of anns.results) {
    const comments = await db.prepare('SELECT * FROM comments WHERE annotation_id = ? ORDER BY created_at').bind(ann.id).all();
    result.push({ ...ann, comments: comments.results });
  }
  return Response.json(result);
}

// DELETE /api/annotations?id=<annotation_id>&commentId=<comment_id>
// - If commentId is provided: delete that single comment. If no comments remain, delete the annotation too.
// - If only id is provided: delete the annotation and all its comments.
export async function onRequestDelete(context) {
  const db = context.env.DB;
  const url = new URL(context.request.url);
  const annId = url.searchParams.get('id');
  const commentId = url.searchParams.get('commentId');
  if (!annId) return new Response('Missing id', { status: 400 });

  if (commentId) {
    await db.prepare('DELETE FROM comments WHERE id = ? AND annotation_id = ?').bind(commentId, annId).run();
    const remaining = await db.prepare('SELECT COUNT(*) as cnt FROM comments WHERE annotation_id = ?').bind(annId).first();
    if (remaining.cnt === 0) {
      await db.prepare('DELETE FROM annotations WHERE id = ?').bind(annId).run();
    }
  } else {
    await db.prepare('DELETE FROM comments WHERE annotation_id = ?').bind(annId).run();
    await db.prepare('DELETE FROM annotations WHERE id = ?').bind(annId).run();
  }

  return Response.json({ ok: true });
}

export async function onRequestPost(context) {
  const db = context.env.DB;
  const body = await context.request.json();
  const { id, text, comment } = body;
  if (!id || !text) return new Response('Missing fields', { status: 400 });

  // Upsert annotation
  await db.prepare('INSERT OR IGNORE INTO annotations (id, text) VALUES (?, ?)').bind(id, text).run();

  // Add comment if provided
  if (comment && comment.text) {
    await db.prepare('INSERT INTO comments (annotation_id, author, text) VALUES (?, ?, ?)')
      .bind(id, comment.author || 'Reviewer', comment.text).run();
  }

  return Response.json({ ok: true });
}
