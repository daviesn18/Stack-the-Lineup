import { parseRosterList } from '../rosterList';

it('reads one player per line, with the number before, after, or after a #', () => {
  expect(parseRosterList('Jake Rivera 4\n  \n12 Connor Walsh\nTyler Van Nguyen #11\nCam')).toEqual([
    { firstName: 'Jake', lastName: 'Rivera', number: '4', positionPreferences: {} },
    { firstName: 'Connor', lastName: 'Walsh', number: '12', positionPreferences: {} },
    { firstName: 'Tyler', lastName: 'Van Nguyen', number: '11', positionPreferences: {} },
    { firstName: 'Cam', lastName: '', number: '', positionPreferences: {} },
  ]);
});
