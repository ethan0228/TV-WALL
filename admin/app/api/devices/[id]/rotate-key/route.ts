import { requireApiAdmin } from "@/app/admin-auth";
import { getDevice, rotateDeviceKey } from "@/db/repository";

export const dynamic = "force-dynamic";

type RouteContext = { params: Promise<{ id: string }> };

export async function POST(_request: Request, context: RouteContext) {
  const auth = await requireApiAdmin();
  if (auth.response) return auth.response;
  const { id } = await context.params;
  if (!(await getDevice(id))) {
    return Response.json({ error: "Device not found" }, { status: 404 });
  }
  return Response.json(await rotateDeviceKey(id));
}
