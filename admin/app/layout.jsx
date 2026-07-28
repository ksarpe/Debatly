import './globals.css';
import AuthGate from '../components/AuthGate';

export const metadata = {
  title: 'Debatly — panel treści',
  description: 'Lokalny panel do edycji pytań i smaczków',
};

export default function RootLayout({ children }) {
  return (
    <html lang="pl">
      <body>
        <AuthGate>{children}</AuthGate>
      </body>
    </html>
  );
}
