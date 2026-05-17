interface TopBarProps {
  name: string;
  email: string;
  role: string;
  initials: string;
  onSignOut: () => void | Promise<void>;
}

export default function TopBar({ name, email, role, initials, onSignOut }: TopBarProps) {
  return (
    <header className="sticky top-0 z-40 flex items-center justify-between px-6 h-14 border-b border-white/5 bg-[#0a0a0f]/80 backdrop-blur-md">
      <p className="text-sm text-gray-400">
        {new Date().toLocaleDateString('en-IN', {
          weekday: 'long',
          year: 'numeric',
          month: 'long',
          day: 'numeric',
        })}
      </p>
      <div className="flex items-center gap-3">
        <div className="hidden text-right md:block">
          <p className="text-sm text-gray-200">{name}</p>
          <p className="text-[11px] uppercase tracking-wider text-gray-500">
            {role}
            {email ? ` · ${email}` : ''}
          </p>
        </div>
        <div className="w-8 h-8 rounded-full bg-indigo-600 flex items-center justify-center text-xs font-bold">
          {initials}
        </div>
        <button
          type="button"
          onClick={onSignOut}
          className="rounded-lg border border-white/10 px-3 py-1.5 text-xs font-medium text-gray-300 transition hover:bg-white/5 hover:text-white"
        >
          Sign Out
        </button>
      </div>
    </header>
  );
}
