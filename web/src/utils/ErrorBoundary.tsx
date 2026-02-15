import { Component, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
}

/** Catches render errors in children (e.g. failed GLB loads crashing Canvas). */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(): State {
    return { hasError: true };
  }

  componentDidCatch(error: Error) {
    console.warn('ErrorBoundary caught:', error.message);
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback ?? (
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          height: '100%', color: '#888', flexDirection: 'column', gap: 8,
        }}>
          <div>Failed to load 3D model</div>
          <button
            onClick={() => this.setState({ hasError: false })}
            style={{
              padding: '6px 16px', background: '#333', border: '1px solid #555',
              borderRadius: 4, color: '#ccc', cursor: 'pointer', fontSize: 12,
            }}
          >
            Retry
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
