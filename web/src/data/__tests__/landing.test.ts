import { hasLanded, markLanded, resetLanding, teamToAutoOpen } from '../landing';

const team = (id: string) => ({ id });

describe('landing after sign-in', () => {
  beforeEach(resetLanding);

  it('opens the only team', () => {
    expect(teamToAutoOpen([team('A')])).toEqual({ id: 'A' });
  });

  it('shows the list for no teams or several', () => {
    expect(teamToAutoOpen([])).toBeNull();
    resetLanding();
    expect(teamToAutoOpen([team('A'), team('B')])).toBeNull();
  });

  it('only auto-opens once, so All teams can show a single team', () => {
    expect(teamToAutoOpen([team('A')])).not.toBeNull();
    expect(teamToAutoOpen([team('A')])).toBeNull();
  });

  it('does not auto-open after the coach has been inside the app', () => {
    markLanded();
    expect(teamToAutoOpen([team('A')])).toBeNull();
  });

  it('starts over after signing out', () => {
    teamToAutoOpen([team('A'), team('B')]);
    expect(hasLanded()).toBe(true);
    resetLanding();
    expect(teamToAutoOpen([team('A')])).toEqual({ id: 'A' });
  });
});
