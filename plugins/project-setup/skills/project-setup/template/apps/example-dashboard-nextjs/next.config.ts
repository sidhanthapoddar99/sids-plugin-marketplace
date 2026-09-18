import { PHASE_DEVELOPMENT_SERVER } from "next/constants";

const need = (key: string) => {
  const value = process.env[key];
  if (!value) throw new Error(`${key} is not set — run through ctl`);
  return value;
};

export default function config(phase: string) {
  return {
    output: "standalone",
    basePath: need("DASHBOARD_PREFIX"),
    async rewrites() {
      if (phase !== PHASE_DEVELOPMENT_SERVER) return [];
      return ["API", "ENGINE"].map((service) => ({
        source: `${need(`${service}_PREFIX`)}/:path*`,
        destination: `http://${need(`${service}_HOST`)}:${need(`${service}_PORT`)}${need(`${service}_PREFIX`)}/:path*`,
        basePath: false,
      }));
    },
  };
}
