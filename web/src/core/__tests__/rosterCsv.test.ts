import { parseRosterCsv, splitCSV, splitFullName } from '../rosterCsv';

// Shaped like a GameChanger Stats export: a group row, then headers, then a Totals row. Names are made up.
const GC = [
  ',,,Batting,,,Pitching',
  'Number,Last,First,GP,PA,AB,IP',
  '4,Rivera,Jake,3,10,9,2.0',
  '7,"Walsh, Jr.",Connor,3,11,10,0.0',
  '',
  'Totals,,,3,21,19,2.0',
].join('\r\n');

describe('parseRosterCsv', () => {
  it('reads a GameChanger export past the group row, skipping Totals', () => {
    expect(parseRosterCsv(GC)).toEqual({
      ok: true,
      players: [
        { firstName: 'Jake', lastName: 'Rivera', number: '4' },
        { firstName: 'Connor', lastName: 'Walsh, Jr.', number: '7' },
      ],
    });
  });
  it('splits a single name column on the last space', () => {
    const r = parseRosterCsv('Player Name,Jersey\nMary Ann Smith,12\nPrince,\n');
    expect(r).toEqual({ ok: true, players: [
      { firstName: 'Mary Ann', lastName: 'Smith', number: '12' },
      { firstName: 'Prince', lastName: '', number: '' },
    ] });
  });
  it('reports empty files, unknown headers and files with no players', () => {
    expect(parseRosterCsv('  \n')).toEqual({ ok: false, error: 'emptyFile' });
    expect(parseRosterCsv('a,b,c\n1,2,3')).toEqual({ ok: false, error: 'malformedHeader' });
    expect(parseRosterCsv('First,Last\n,\nTotals,')).toEqual({ ok: false, error: 'noValidPlayersFound' });
  });
});

describe('CSV helpers', () => {
  it('handles quotes, escaped quotes and mixed line endings', () => {
    expect(splitCSV('a,"b,c","d ""e"""\r\nf\rg\n')).toEqual([['a', 'b,c', 'd "e"'], ['f'], ['g']]);
  });
  it('splitFullName keeps one word as the first name', () => {
    expect(splitFullName('  Cher ')).toEqual({ first: 'Cher', last: '' });
  });
});
