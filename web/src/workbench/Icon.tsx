// SF Symbols aren't licensed for the web, so the web uses Lucide stand-ins,
// looked up by the SF Symbol name the design (and the iOS app) uses.

import type { CSSProperties } from 'react';

import {
  Archive, ArrowRight, Calendar, Check, CalendarPlus, ChevronDown, ChevronLeft, ChevronRight, ChevronUp, CircleCheck, CircleMinus, CirclePlus, Diamond, Download,
  FileText, GripVertical, History, Info, ListOrdered, Pencil, PersonStanding, Plus, Settings, Share, ShieldCheck, Trash2, TriangleAlert, UserPlus, Users, Zap,
  type LucideIcon,
} from 'lucide-react';

const MAP: Record<string, LucideIcon> = {
  'person.3.fill': Users,
  'list.number': ListOrdered,
  'baseball.diamond.bases': Diamond,
  'clock.arrow.circlepath': History,
  calendar: Calendar,
  'calendar.badge.plus': CalendarPlus,
  archivebox: Archive,
  'gearshape.fill': Settings,
  gearshape: Settings,
  'plus.circle.fill': CirclePlus,
  'plus.circle': CirclePlus,
  'checkmark.circle.fill': CircleCheck,
  checkmark: Check,
  'minus.circle.fill': CircleMinus,
  'person.badge.plus': UserPlus,
  'chevron.down': ChevronDown,
  'chevron.right': ChevronRight,
  'chevron.left': ChevronLeft,
  'chevron.up': ChevronUp,
  plus: Plus,
  'bolt.fill': Zap,
  'checkmark.shield.fill': ShieldCheck,
  'exclamationmark.triangle.fill': TriangleAlert,
  'doc.text': FileText,
  'doc.richtext.fill': FileText,
  'square.and.arrow.up': Share,
  'square.and.arrow.down': Download,
  'info.circle': Info,
  'arrow.right': ArrowRight,
  grip: GripVertical,
  'figure.baseball.pitcher': PersonStanding,
  pencil: Pencil,
  trash: Trash2,
};

const FILLED = new Set(['checkmark.circle.fill', 'plus.circle.fill', 'minus.circle.fill', 'checkmark.shield.fill', 'exclamationmark.triangle.fill', 'bolt.fill']);

export function Icon({ name, size = 18, color = 'currentColor', style }: { name: string; size?: number; color?: string; style?: CSSProperties }) {
  const Glyph = MAP[name] ?? Info;
  // Filled symbols: a solid shape with the glyph's lines knocked out in white.
  if (FILLED.has(name)) {
    const line = name === 'bolt.fill' ? color : '#fff';
    return <Glyph size={size} color={line} fill={color} strokeWidth={2.2} style={{ flexShrink: 0, ...style }} aria-hidden />;
  }
  return <Glyph size={size} color={color} strokeWidth={1.9} style={{ flexShrink: 0, ...style }} aria-hidden />;
}
