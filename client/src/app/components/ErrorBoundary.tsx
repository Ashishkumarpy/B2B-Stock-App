import { Component, type ErrorInfo, type ReactNode } from 'react';

type Props = {
  children: ReactNode;
};

type State = {
  hasError: boolean;
  errorMessage?: string;
};

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(error: unknown): State {
    const message = error instanceof Error ? error.message : String(error);
    return { hasError: true, errorMessage: message };
  }

  componentDidCatch(error: unknown, info: ErrorInfo) {
    // Keep a console signal for debugging when the UI fails to render.
    // eslint-disable-next-line no-console
    console.error('Client render error:', error, info);
  }

  render() {
    if (!this.state.hasError) return this.props.children;

    return (
      <div className="min-h-screen bg-black text-white flex items-center justify-center p-8">
        <div className="max-w-xl w-full border border-white/10 bg-white/5 p-6">
          <h1 className="text-xl uppercase tracking-wider mb-3">Something broke</h1>
          <p className="text-sm text-gray-300 mb-4">
            The UI hit a runtime error. Check the browser console for the full stack trace.
          </p>
          {this.state.errorMessage && (
            <pre className="text-xs text-gray-200 whitespace-pre-wrap break-words border border-white/10 bg-black/40 p-3">
              {this.state.errorMessage}
            </pre>
          )}
        </div>
      </div>
    );
  }
}

