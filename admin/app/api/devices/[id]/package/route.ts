import { requireApiAdmin } from "@/app/admin-auth";
import { buildInstallationPackage } from "@/app/install-package";
import { getDevice, getDeviceApiKey } from "@/db/repository";

export const dynamic = "force-dynamic";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(request: Request, context: RouteContext) {
  const auth = await requireApiAdmin();
  if (auth.response) return auth.response;

  const { id } = await context.params;
  const device = await getDevice(id);
  if (!device) {
    return Response.json({ error: "Device not found" }, { status: 404 });
  }

  try {
    const apiKey = await getDeviceApiKey(id);
    if (!apiKey) {
      return Response.json({ error: "Device not found" }, { status: 404 });
    }
    const { bytes, filename } = buildInstallationPackage(
      device,
      apiKey,
      new URL(request.url).origin,
    );
    return new Response(bytes, {
      headers: {
        "cache-control": "private, no-store",
        "content-disposition": `attachment; filename="${filename}"; filename*=UTF-8''${encodeURIComponent(filename)}`,
        "content-type": "application/zip",
        "x-content-type-options": "nosniff",
      },
    });
  } catch (error) {
    return Response.json(
      {
        error:
          error instanceof Error
            ? error.message
            : "Unable to generate installation package",
      },
      { status: 500 },
    );
  }
}
