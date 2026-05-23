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
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: `
              try {
                const theme = localStorage.getItem('theme') || 'dark';
                if (theme === 'dark') {
                  document.documentElement.classList.add('dark');
                } else {
                  document.documentElement.classList.remove('dark');
                }
              } catch (_) {}
            `,
          }}
        />
      </head>
      <body className="transition-colors duration-200">
        <AuthShell>{children}</AuthShell>
      </body>
    </html>
  );
}
