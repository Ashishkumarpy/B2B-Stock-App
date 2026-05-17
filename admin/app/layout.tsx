import type { Metadata } from 'next';
import './globals.css';
import AuthShell from '@/components/AuthShell';

export const metadata: Metadata = {
  title: 'B2B Stock Admin',
  description: 'Internal admin dashboard for B2B Stock Platform.',
};

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-[#0a0a0f] text-white">
        <AuthShell>{children}</AuthShell>
      </body>
    </html>
  );
}
