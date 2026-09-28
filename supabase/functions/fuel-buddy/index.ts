import { createHandler } from "./handler.ts";

Deno.serve(createHandler({ env: (name) => Deno.env.get(name), fetch }));
