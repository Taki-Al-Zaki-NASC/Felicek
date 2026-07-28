/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Public job listings are the reason this exists as a separate stack rather
  // than Flutter Web: they have to be server-rendered to be indexable.
  typedRoutes: true,
};
export default nextConfig;
