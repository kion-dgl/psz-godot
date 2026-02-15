import { Link } from 'react-router-dom';

export default function Landing() {
  return (
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      height: '100%',
      gap: 32,
      padding: 32,
    }}>
      <h1 style={{ fontSize: 28, fontWeight: 300, letterSpacing: 2 }}>
        Phantasy Star Zero
      </h1>
      <p style={{ color: '#888', fontSize: 14, maxWidth: 480, textAlign: 'center', lineHeight: 1.6 }}>
        Fan-made recreation of Phantasy Star Zero. Quest editor, element storybook,
        and downloadable game client.
      </p>
      <div style={{ display: 'flex', gap: 16, marginTop: 16 }}>
        <Link to="/quest-editor" style={{
          padding: '10px 24px',
          background: '#2a2a5a',
          color: '#88aaff',
          textDecoration: 'none',
          borderRadius: 6,
          fontSize: 14,
          border: '1px solid #3a3a6a',
        }}>
          Quest Editor
        </Link>
        <Link to="/storybook" style={{
          padding: '10px 24px',
          background: '#2a2a5a',
          color: '#88aaff',
          textDecoration: 'none',
          borderRadius: 6,
          fontSize: 14,
          border: '1px solid #3a3a6a',
        }}>
          Storybook
        </Link>
      </div>
    </div>
  );
}
