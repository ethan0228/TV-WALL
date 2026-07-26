import { clearLocalSessionCookie, getLocalAuthConfig } from "@/app/local-auth";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  return logout(request);
}

export async function GET(request: Request) {
  return logout(request);
}

function logout(request: Request) {
  if (!getLocalAuthConfig()) return new Response("Not found", { status: 404 });
  const secure = new URL(request.url).protocol === "https:";
  return new Response(null, {
    status: 303,
    headers: {
      location: new URL("/login", request.url).toString(),
      "set-cookie": clearLocalSessionCookie(secure),
      "cache-control": "no-store",
    },
  });
}
