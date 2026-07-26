import { requireApiAdmin } from "@/app/admin-auth";
import { validateDeviceInput } from "@/app/api/devices/route";
import { deleteDevice, getDevice, updateDevice } from "@/db/repository";

export const dynamic = "force-dynamic";

type RouteContext = { params: Promise<{ id: string }> };

export async function PATCH(request: Request, context: RouteContext) {
  const auth = await requireApiAdmin();
  if (auth.response) return auth.response;
  const { id } = await context.params;
  if (!(await getDevice(id))) {
    return Response.json({ error: "Device not found" }, { status: 404 });
  }
  try {
    const input = validateDeviceInput(await request.json());
    return Response.json({ device: await updateDevice(id, input) });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Invalid request" },
      { status: 400 },
    );
  }
}

export async function DELETE(_request: Request, context: RouteContext) {
  const auth = await requireApiAdmin();
  if (auth.response) return auth.response;
  const { id } = await context.params;
  if (!(await getDevice(id))) {
    return Response.json({ error: "Device not found" }, { status: 404 });
  }
  await deleteDevice(id);
  return new Response(null, { status: 204 });
}
