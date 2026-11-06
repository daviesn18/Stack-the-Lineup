// First run and What's New (iOS WelcomeView and WhatsNewView, sized for the
// web). A coach sees the welcome once in this browser, and What's New once per
// WHATS_NEW.version after that. The welcome stands in for both on a first
// visit, so a new coach isn't shown two dialogs. Either can be reopened from
// the ⌘K palette.
//
// Seen-state lives in localStorage: it's a per-browser convenience, and if
// storage is blocked the dialog simply shows again next time.

import { useEffect, useState } from 'react';

import { signal } from '@/data/analytics';

import { Icon } from './Icon';
import { PrimaryButton, SecondaryButton, SUB } from './Shell';
import { C } from './theme';

const WELCOME_KEY = 'stl.welcome.seen';
const WHATS_NEW_KEY = 'stl.whatsNew.seen';

interface Item { icon: string; color: string; title: string; body: string }

const WELCOME: Item[] = [
  {
    icon: 'baseball.diamond.bases', color: C.blue, title: 'Welcome to Stack the Lineup.',
    body: 'Build a fair lineup, assign every inning, and hand out the PDF before first pitch.',
  },
  {
    icon: 'checkmark.shield.fill', color: C.green, title: 'Fair play, tracked for you.',
    body: "Set your league's rules once: fielding minimums, bench limits, pitching caps. The lineup flags a problem the moment you create one.",
  },
  {
    icon: 'bolt.fill', color: C.orange, title: 'Fast on a keyboard.',
    body: 'Click any spot on the grid to pick a player, or right-click a player for their options. Choose several innings to set a whole stretch at once. ⌘K jumps to any page, player or game.',
  },
];

export const WHATS_NEW = {
  version: '2026-11',
  items: [
    {
      icon: 'calendar.badge.plus', color: C.blue, title: 'A lineup for each game',
      body: 'Games from your imported schedule are on Home. Pick one to build it; each keeps its own batting order, positions and Finalized status.',
    },
    {
      icon: 'square.and.arrow.down', color: C.green, title: 'Export your team',
      body: 'Team settings › Export downloads a .stlteam file to import in Stack the Lineup on iPhone, or back here.',
    },
    {
      icon: 'doc.text', color: C.teal, title: 'Game Recap',
      body: 'Open an archived game to see who pitched and whether your fair play rules held up. Copy it to send to parents.',
    },
    {
      icon: 'list.number', color: C.orange, title: 'Set several innings at once',
      body: 'The player picker and the right-click menu now take a run of innings, so "Caleb pitches 1 to 3" is one click.',
    },
    {
      icon: 'person.3.fill', color: C.blue, title: 'Hitting Archetypes',
      body: "Give each hitter a quick scouting card: Power, Gap or Singles, plus speed and OBP. It's in the player panel.",
    },
  ] as Item[],
};

const read = (k: string) => { try { return localStorage.getItem(k); } catch { return null; } };
const write = (k: string, v: string) => { try { localStorage.setItem(k, v); } catch { /* blocked: shows again next visit */ } };

export type IntroKind = 'welcome' | 'whatsNew';

/** Which dialog this browser should see on opening a team, if any. */
export function dueIntro(): IntroKind | null {
  if (!read(WELCOME_KEY)) return 'welcome';
  return read(WHATS_NEW_KEY) === WHATS_NEW.version ? null : 'whatsNew';
}

/** Opens itself on first visit or a new What's New; `forced` reopens one from the palette. */
export function Intro({ forced, onClosed }: { forced: IntroKind | null; onClosed(): void }) {
  // The workbench only renders in the browser (after sign-in), so storage is readable on first render.
  const [auto, setAuto] = useState<IntroKind | null>(() => (typeof window === 'undefined' ? null : dueIntro()));
  const kind = forced ?? auto;
  if (!kind) return null;
  const close = (completed: boolean) => {
    write(WELCOME_KEY, '1');
    write(WHATS_NEW_KEY, WHATS_NEW.version);
    if (kind === 'welcome') signal(completed ? 'tour.welcome.completed' : 'tour.welcome.skipped');
    else signal('whatsnew.viewed', { version: WHATS_NEW.version });
    setAuto(null);
    onClosed();
  };
  return kind === 'welcome' ? <Welcome onClose={close} /> : <WhatsNew onClose={() => close(true)} />;
}

function Shell({ label, onClose, children, footer }: { label: string; onClose(): void; children: React.ReactNode; footer: React.ReactNode }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{ position: 'fixed', inset: 0, zIndex: 50, background: 'rgba(0,0,0,0.35)', display: 'grid', placeItems: 'center', padding: 24 }}>
      <div role="dialog" aria-modal aria-label={label} className="pop"
        style={{ width: 520, maxWidth: '100%', maxHeight: 'calc(100vh - 48px)', background: '#fff', borderRadius: 16, overflow: 'hidden', display: 'flex', flexDirection: 'column', boxShadow: '0 16px 40px rgba(0,0,0,0.22)' }}>
        <div style={{ flex: 1, overflowY: 'auto', padding: '28px 28px 8px' }}>{children}</div>
        <div style={{ padding: '14px 20px', display: 'flex', alignItems: 'center', gap: 8 }}>{footer}</div>
      </div>
    </div>
  );
}

function Badge({ icon, color, size = 44 }: { icon: string; color: string; size?: number }) {
  return (
    <span style={{ width: size, height: size, borderRadius: size / 4, background: `${color}1F`, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
      <Icon name={icon} size={size / 2} color={color} />
    </span>
  );
}

function Welcome({ onClose }: { onClose(completed: boolean): void }) {
  const [page, setPage] = useState(0);
  const card = WELCOME[page];
  const last = page === WELCOME.length - 1;
  return (
    <Shell label="Welcome" onClose={() => onClose(false)}
      footer={(
        <>
          <span style={{ display: 'flex', gap: 6 }} aria-label={`Page ${page + 1} of ${WELCOME.length}`}>
            {WELCOME.map((_, i) => <span key={i} style={{ width: 7, height: 7, borderRadius: 4, background: i === page ? C.blue : C.gray5 }} />)}
          </span>
          <span style={{ marginLeft: 'auto', display: 'flex', gap: 8 }}>
            {!last && <SecondaryButton onClick={() => onClose(false)}>Skip</SecondaryButton>}
            <PrimaryButton height={32} onClick={() => (last ? onClose(true) : setPage(page + 1))}>{last ? 'Get started' : 'Next'}</PrimaryButton>
          </span>
        </>
      )}>
      <Badge icon={card.icon} color={card.color} size={56} />
      <h2 style={{ fontSize: 24, fontWeight: 700, letterSpacing: '-0.01em', margin: '18px 0 8px' }}>{card.title}</h2>
      <p style={{ fontSize: 16, lineHeight: '23px', color: SUB, margin: '0 0 12px' }}>{card.body}</p>
    </Shell>
  );
}

function WhatsNew({ onClose }: { onClose(): void }) {
  return (
    <Shell label="What's new" onClose={onClose}
      footer={<span style={{ marginLeft: 'auto' }}><PrimaryButton height={32} onClick={onClose}>Continue</PrimaryButton></span>}>
      <h2 style={{ fontSize: 24, fontWeight: 700, letterSpacing: '-0.01em', margin: '0 0 4px' }}>What&apos;s new</h2>
      <p style={{ fontSize: 14, color: SUB, margin: '0 0 18px' }}>New on the web, matching Stack the Lineup on iPhone.</p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16, paddingBottom: 12 }}>
        {WHATS_NEW.items.map((it) => (
          <div key={it.title} style={{ display: 'flex', gap: 14 }}>
            <Badge icon={it.icon} color={it.color} size={38} />
            <span>
              <span style={{ display: 'block', fontSize: 15, fontWeight: 600 }}>{it.title}</span>
              <span style={{ display: 'block', fontSize: 14, lineHeight: '20px', color: SUB, marginTop: 2 }}>{it.body}</span>
            </span>
          </div>
        ))}
      </div>
    </Shell>
  );
}
