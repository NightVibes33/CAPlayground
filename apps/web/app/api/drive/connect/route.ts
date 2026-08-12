import { NextRequest, NextResponse } from 'next/server';

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID!;
export const runtime = 'nodejs';

export async function GET(request: NextRequest) {
  try {
    const url = new URL(request.url);
    const origin = `${url.protocol}//${url.host}`;

    const redirectUri = `${origin}/api/drive/callback`;
    const native = url.searchParams.get('native') === '1';
    const nativeState = url.searchParams.get('state');
    const params = new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID,
      redirect_uri: redirectUri,
      response_type: 'code',
      scope: [
        'https://www.googleapis.com/auth/drive.file',
        'https://www.googleapis.com/auth/userinfo.email'
      ].join(' '),
      access_type: 'offline',
      prompt: 'consent'
    });
    if (native) {
      if (!nativeState) return NextResponse.json({ error: 'Missing native state' }, { status: 400 });
      params.set('state', `native:${nativeState}`);
    }
    const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;

    if (native) return NextResponse.redirect(authUrl);

    return NextResponse.json({ authUrl });

  } catch (error: any) {
    console.error('Drive connect error:', error);
    return NextResponse.json({ 
      error: 'Failed to generate auth URL',
      details: error.message 
    }, { status: 500 });
  }
}
