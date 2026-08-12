import { NextRequest, NextResponse } from "next/server"
import { activeDriveSession } from "../mobile-session"
export const runtime = "nodejs"

async function session(request: NextRequest) {
  const opaque = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "")
  if (!opaque) throw new Error("Google Drive not connected")
  return activeDriveSession(opaque)
}
function response(body: unknown, sealed?: string, status = 200) { const value = NextResponse.json(body, { status }); if (sealed) value.headers.set("X-Drive-Session", sealed); return value }
async function driveJSON(url: string, token: string, init: RequestInit = {}) { const result = await fetch(url, { ...init, headers: { Authorization: `Bearer ${token}`, ...(init.headers || {}) } }); if (!result.ok) throw new Error(await result.text()); return result.status === 204 ? null : result.json() }
const folderQueryURL = "https://www.googleapis.com/drive/v3/files?q=" + encodeURIComponent("name='CAPlayground' and mimeType='application/vnd.google-apps.folder' and trashed=false") + "&fields=files(id,name)&spaces=drive"

export async function GET(request: NextRequest) {
  try {
    const { session: auth, sealed } = await session(request), token = auth.accessToken
    const folders = await driveJSON(folderQueryURL, token)
    if (!folders.files?.length) return response({ files: [] }, sealed)
    const q = `'${folders.files[0].id}' in parents and trashed=false and mimeType='application/zip'`
    const files = await driveJSON("https://www.googleapis.com/drive/v3/files?q=" + encodeURIComponent(q) + "&fields=files(id,name,webViewLink,createdTime,size)&orderBy=createdTime%20desc&spaces=drive", token)
    return response({ files: files.files || [] }, sealed)
  } catch (error: any) { return response({ error: error.message }, undefined, 403) }
}

export async function POST(request: NextRequest) {
  try {
    const { session: auth, sealed } = await session(request), token = auth.accessToken
    const body = await request.json() as { action: string; fileId?: string; name?: string; zipData?: string }
    if (body.action === "download" && body.fileId) {
      const result = await fetch(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(body.fileId)}?alt=media`, { headers: { Authorization: `Bearer ${token}` } }); if (!result.ok) throw new Error(await result.text())
      return response({ zipData: Buffer.from(await result.arrayBuffer()).toString("base64") }, sealed)
    }
    if (body.action === "delete" && body.fileId) { await driveJSON(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(body.fileId)}`, token, { method: "DELETE" }); return response({ success: true }, sealed) }
    if (body.action === "deleteAll") {
      const folders = await driveJSON(folderQueryURL, token)
      const folderId = folders.files?.[0]?.id
      if (folderId) await driveJSON(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(folderId)}`, token, { method: "DELETE" })
      return response({ success: true }, sealed)
    }
    if (body.action === "upload" && body.name && body.zipData) {
      const folderQuery = await driveJSON(folderQueryURL, token)
      let folderId = folderQuery.files?.[0]?.id
      if (!folderId) { const folder = await driveJSON("https://www.googleapis.com/drive/v3/files", token, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ name: "CAPlayground", mimeType: "application/vnd.google-apps.folder" }) }); folderId = folder.id }
      const fileName = `${body.name}.ca.zip`
      let replaceId = body.fileId
      if (!replaceId) {
        const q = `'${folderId}' in parents and trashed=false and name='${fileName.replace(/'/g, "\\'")}'`
        const existing = await driveJSON("https://www.googleapis.com/drive/v3/files?q=" + encodeURIComponent(q) + "&fields=files(id)&pageSize=1&spaces=drive", token)
        replaceId = existing.files?.[0]?.id
      }
      const metadata: any = { name: fileName, description: `CAPlayground project: ${body.name}` }
      if (!replaceId) metadata.parents = [folderId]
      const boundary = `caplayground-${crypto.randomUUID()}`, bytes = Buffer.from(body.zipData, "base64")
      const multipart = Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n--${boundary}\r\nContent-Type: application/zip\r\n\r\n`), bytes, Buffer.from(`\r\n--${boundary}--`)] )
      const endpoint = replaceId
        ? `https://www.googleapis.com/upload/drive/v3/files/${encodeURIComponent(replaceId)}?uploadType=multipart&fields=id,name,webViewLink,createdTime,size`
        : "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink,createdTime,size"
      const uploaded = await driveJSON(endpoint, token, { method: replaceId ? "PATCH" : "POST", headers: { "Content-Type": `multipart/related; boundary=${boundary}` }, body: multipart })
      return response({ success: true, file: uploaded, updated: !!replaceId }, sealed)
    }
    return response({ error: "Invalid action" }, sealed, 400)
  } catch (error: any) { return response({ error: error.message }, undefined, 403) }
}
