import crypto from "crypto"

export interface MobileDriveSession { accessToken: string; refreshToken?: string; expiresAt?: number }
const key = () => crypto.createHash("sha256").update(process.env.GOOGLE_CLIENT_SECRET!).digest()
const encode = (value: Buffer) => value.toString("base64url")

export function sealDriveSession(session: MobileDriveSession): string {
  const iv = crypto.randomBytes(12), cipher = crypto.createCipheriv("aes-256-gcm", key(), iv)
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(session), "utf8"), cipher.final()])
  return [encode(iv), encode(cipher.getAuthTag()), encode(encrypted)].join(".")
}

export function openDriveSession(value: string): MobileDriveSession {
  const [iv, tag, encrypted] = value.split(".").map(part => Buffer.from(part, "base64url"))
  if (!iv || !tag || !encrypted) throw new Error("Invalid Drive session")
  const decipher = crypto.createDecipheriv("aes-256-gcm", key(), iv); decipher.setAuthTag(tag)
  return JSON.parse(Buffer.concat([decipher.update(encrypted), decipher.final()]).toString("utf8"))
}

export async function activeDriveSession(value: string): Promise<{ session: MobileDriveSession; sealed?: string }> {
  const session = openDriveSession(value)
  if (!session.expiresAt || Date.now() < session.expiresAt - 60_000) return { session }
  if (!session.refreshToken) throw new Error("Google Drive session expired")
  const response = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "refresh_token", client_id: process.env.GOOGLE_CLIENT_ID!, client_secret: process.env.GOOGLE_CLIENT_SECRET!, refresh_token: session.refreshToken }) })
  if (!response.ok) throw new Error("Failed to refresh Google Drive session")
  const result = await response.json() as { access_token: string; expires_in?: number }
  const refreshed = { ...session, accessToken: result.access_token, expiresAt: Date.now() + (result.expires_in ?? 3600) * 1000 }
  return { session: refreshed, sealed: sealDriveSession(refreshed) }
}
