import { NextRequest, NextResponse } from "next/server"
import { App } from "octokit"
import { createClient } from "@supabase/supabase-js"

export const runtime = "nodejs"

export async function POST(request: NextRequest) {
  try {
    const bearer = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "")
    if (!bearer) return NextResponse.json({ error: "You must be signed in to submit." }, { status: 401 })

    const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
      global: { headers: { Authorization: `Bearer ${bearer}` } }, auth: { persistSession: false }
    })
    const { data: auth, error: authError } = await supabase.auth.getUser(bearer)
    if (authError || !auth.user) return NextResponse.json({ error: "You must be signed in to submit." }, { status: 401 })

    const body = await request.json() as { name?: string; description?: string; username?: string; tendiesBase64?: string; videoBase64?: string; videoExtension?: string }
    const name = body.name?.trim(), description = body.description?.trim(), username = body.username?.trim() || "Anonymous"
    if (!name || name.length > 42 || !description || description.length > 60 || !body.tendiesBase64 || !body.videoBase64) {
      return NextResponse.json({ error: "Name, description, .tendies file, and preview video are required." }, { status: 400 })
    }
    const { count } = await supabase.from("wallpaper_submissions").select("id", { count: "exact", head: true }).eq("user_id", auth.user.id).eq("status", "awaiting_review")
    if ((count ?? 0) >= 5) return NextResponse.json({ error: "You already have 5 wallpapers awaiting review." }, { status: 409 })

    const app = new App({ appId: process.env.GITHUB_APP_ID!, privateKey: process.env.GITHUB_APP_PRIVATE_KEY!.replace(/\\n/g, "\n") })
    const octokit = await app.getInstallationOctokit(Number(process.env.GITHUB_INSTALLATION_ID!))
    const owner = "CAPlayground", repo = "wallpapers", wallpaperId = Math.floor(Math.random() * 9_000_000) + 1_000_000
    const safeName = name.replace(/[^a-z0-9]/gi, "_")
    const slug = (username || "user").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "user"
    const branch = `${slug}/${wallpaperId}`
    const ref = await octokit.rest.git.getRef({ owner, repo, ref: "heads/dev" })
    const commit = await octokit.rest.git.getCommit({ owner, repo, commit_sha: ref.data.object.sha })
    const [tendies, video, json] = await Promise.all([
      octokit.rest.git.createBlob({ owner, repo, content: body.tendiesBase64, encoding: "base64" }),
      octokit.rest.git.createBlob({ owner, repo, content: body.videoBase64, encoding: "base64" }),
      octokit.rest.git.createBlob({ owner, repo, content: JSON.stringify({ name, id: wallpaperId, creator: username, description, file: `wallpapers/${safeName}.tendies`, preview: `previews/gif/${safeName}.gif`, date: Date.now(), from: "website" }, null, 2), encoding: "utf-8" })
    ])
    const tree = await octokit.rest.git.createTree({ owner, repo, base_tree: commit.data.tree.sha, tree: [
      { path: `wallpapers/${safeName}.tendies`, mode: "100644", type: "blob", sha: tendies.data.sha },
      { path: `previews/video/${safeName}.${(body.videoExtension || "mp4").replace(/[^a-z0-9]/gi, "")}`, mode: "100644", type: "blob", sha: video.data.sha },
      { path: `jsons/${safeName}.json`, mode: "100644", type: "blob", sha: json.data.sha }
    ] })
    const next = await octokit.rest.git.createCommit({ owner, repo, message: `Add wallpaper: ${name}`, tree: tree.data.sha, parents: [ref.data.object.sha] })
    await octokit.rest.git.createRef({ owner, repo, ref: `refs/heads/${branch}`, sha: next.data.sha })
    const raw = `https://raw.githubusercontent.com/${owner}/${repo}/${encodeURIComponent(branch)}/wallpapers/${safeName}.tendies`
    const pr = await octokit.rest.pulls.create({ owner, repo, title: `Submission: ${name}`, base: "dev", head: branch, body: `Wallpaper submission from ${username}\n\nDescription: ${description}\nID: ${wallpaperId}\n[Download .tendies file](${raw})` })
    const { error: dbError } = await supabase.from("wallpaper_submissions").insert({ id: wallpaperId, user_id: auth.user.id, name, description, status: "awaiting_review", github_username: username })
    if (dbError) throw dbError
    return NextResponse.json({ success: true, pullRequestURL: pr.data.html_url, submissionId: wallpaperId })
  } catch (error: any) {
    console.error("Wallpaper submission error", error)
    return NextResponse.json({ error: error?.message || "Failed to submit wallpaper" }, { status: 500 })
  }
}
