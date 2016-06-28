import std.stdio;
import deimos.ncurses.ncurses;
import jsonizer;
import std.conv, std.string, std.datetime, core.thread, std.math;
import std.algorithm : remove, sum;
shared int row, col;
struct Run {
	mixin JsonizeMe;

	@jsonize {
		float[] splits;
		bool[] gold;
	}
};

struct Game {
	mixin JsonizeMe;

	@jsonize {
		string name;
		string[] splitnames;
		Run[] runs;
		float[] best;
		size_t pb;
	}

	bool dirty = false;
	string path;
};

WINDOW *statusbar;

class wins {
	WINDOW *main;
	WINDOW *b;
	~this() {
		wclear(main);
		wclear(b);
		wrefresh(b);
		wrefresh(main);
		delwin(b);
		delwin(main);
		refresh();
	}
};

wins create_window(int h, int w, int y, int x)
{
	wins wins = new wins;
	wins.main = newwin(h-2, w-2, y+1, x+1);
	wins.b = newwin(h, w, y, x);
	box(wins.b, 0, 0);
	refresh();
	wrefresh(wins.b);
	wrefresh(wins.main);
	return wins;
}

float get_personal_best(Game *game)
{
	if(game.runs.length == 0) {
		return float.infinity;
	}
	return game.runs[game.pb].splits[$-1];
}

void run(Game *game)
{
	int ncd = (row - 7) / 2 - 1;
	scope auto wins = create_window(row - 5, col + 1, 3, 0);
	mvwprintw(wins.b, 0, 2, "[RUNNING]");
	wrefresh(wins.b);

	WINDOW *stats = newwin(1, col+1, 0, 0);
	wbkgd(stats, COLOR_PAIR(1));
	wclear(stats);
	refresh();
	wprintw(stats, "Running ");
	wprintw(stats, toStringz(game.name));
	wprintw(stats, " | ");
	wprintw(stats, "Personal Best: %1.1f | Sum of Best: %1.1f", get_personal_best(game), game.best.length > 0 ? game.best[$-1] : float.infinity);
	wrefresh(stats);

	auto run = new Run;
	auto pb = game.runs.length > 0 ? &game.runs[game.pb] : null;
	nodelay(wins.main, true);

	auto sw = new StopWatch;
	sw.start();
	size_t split = 0;
	bool success = false;
	while(true) {
		wclear(wins.main);
		mvwprintw(wins.main, 0, 0, "Split Name              Personal Best               Current  Time            Difference\n");
		mvwprintw(wins.main, 1, 0, "                      Split       Total           Split       Total");
		int line = 0;
		for(size_t i=0;i<game.splitnames.length;i++) {
			if(abs(cast(int)i - cast(int)split) >= ncd)
				continue;
			if(i == split)
				wattron(wins.main, A_BOLD);
			mvwprintw(wins.main, cast(int)line*2+2, 0, "%-20s", toStringz(game.splitnames[i]));
			wattroff(wins.main, A_BOLD);
			float pbsec = pb == null ? float.infinity : pb.splits[i];
			float prev = pb == null ? float.infinity : (i == 0 ? 0 : pb.splits[i-1]);
			float diff = pb == null ? float.infinity : pbsec - prev;

			if(pbsec != float.infinity) {
				wprintw(wins.main, "%02.0f:%04.1f     ", diff / 60, cast(float)fmod(diff, 60.0));
				wprintw(wins.main, "%02.0f:%04.1f", pbsec / 60, cast(float)fmod(pbsec, 60.0));
			}

			float sec = sw.peek().msecs / 1000.0;
			prev = (i == 0 || i > run.splits.length) ? 0 : run.splits[i-1];
			if(split == i) {
				mvwprintw(wins.main, cast(int)line*2+2, 48, "%02.0f:%04.1f    ", (sec - prev) / 60, cast(float)fmod(sec - prev, 60.0));
				mvwprintw(wins.main, cast(int)line*2+2, 60, "%02.0f:%04.1f    ", sec / 60, cast(float)fmod(sec, 60.0));
			} else if(i < split) {
				mvwprintw(wins.main, cast(int)line*2+2, 48, "%02.0f:%04.1f    ",
						(run.splits[i] - prev) / 60, cast(float)fmod((run.splits[i] - prev), 60.0));
				mvwprintw(wins.main, cast(int)line*2+2, 60, "%02.0f:%04.1f    ",
						run.splits[i] / 60, cast(float)fmod(run.splits[i], 60.0));
			}

			if(pbsec != float.infinity && i <= split) {
				if(i != split)
					sec = run.splits[i];
				if(i < split && run.gold[i]) {
					wattron(wins.main, COLOR_PAIR(2) | A_BOLD);
				} else if(sec - pbsec < 0) {
					wattron(wins.main, COLOR_PAIR(3) | A_BOLD);
				} else {
					wattron(wins.main, COLOR_PAIR(4) | A_BOLD);
				}
				mvwprintw(wins.main, cast(int)line*2+2, 78, "%c%02.0f:%04.1f",
						(sec - pbsec) < 0 ? '-' : ' ', fabs(sec - pbsec) / 60, cast(float)fmod(fabs(sec - pbsec), 60.0));
				wrefresh(wins.main);
				refresh();
				
				wattroff(wins.main, A_BOLD);
				wattroff(wins.main, COLOR_PAIR(2));
				wattroff(wins.main, COLOR_PAIR(3));
				wattroff(wins.main, COLOR_PAIR(4));
				wattron(wins.main, COLOR_PAIR(0));
			}
			line++;
		}

		wrefresh(wins.main);
		if(success)
			break;

		int c = wgetch(wins.main);
		if(c == 'q') {
			sw.stop();
			break;
		} else if(c == ' ') {
			run.splits ~= sw.peek().msecs / 1000.0;
			if(split >= game.best.length) {
				game.best ~= sw.peek().msecs / 1000.0;
				run.gold ~= true;
			} else if(game.best[split] > sw.peek().msecs / 1000.0) {
				game.best[split] = sw.peek().msecs / 1000.0;
				run.gold ~= true;
			} else {
				run.gold ~= false;
			}
			split++;
			if(split >= game.splitnames.length) {
				sw.stop();
				success = true;
			}
		}
		Thread.sleep( dur!("msecs")( 50 ) );
	}

	nodelay(wins.main, false);
	if(success) {
		mvwprintw(wins.main, row-8, 0, "Completed - time: %1.1f. Do you want to save these splits (Y/n)? ", sw.peek().msecs / 1000.0);
		wrefresh(wins.main);
		int c = wgetch(wins.main);
		wprintw(wins.main, "%c", cast(char)c);

		if(c != 'n') {
			game.runs ~= *run;
			game.dirty = true;
			if(sum(run.splits) < get_personal_best(game)) {
				game.pb = game.runs.length - 1;
			}
		}
	}

	wbkgd(stats, COLOR_PAIR(0));
	wclear(stats);
	wrefresh(stats);
	delwin(stats);
	refresh();
}

void save_game(Game *g)
{
	scope auto wins = create_window(3, col+1, row/2, 0);
	mvwprintw(wins.b, 0, 2, "[Save Game]");
	wrefresh(wins.b);

	wprintw(wins.main, "Path to save game data");
	if(g.path != "") {
		wprintw(wins.main, " [");
		wprintw(wins.main, toStringz(g.path));
		wprintw(wins.main, "]");
	}
	wprintw(wins.main, ": ");
	wrefresh(wins.main);
	
	string path;
	read_string(wins.main, path);
	if(path != "")
		g.path = path;

	scope File save = File(g.path, "w+");
	save.writeln(toJSON(g));
	save.close();
	g.dirty = false;
}

auto open_game()
{
	string path;
	{
		scope auto wins = create_window(3, col+1, row/2, 0);
		mvwprintw(wins.b, 0, 2, "[Open Game]");
		wrefresh(wins.b);

		wprintw(wins.main, "Path to game data file: ");
		wrefresh(wins.main);
		read_string(wins.main, path);
	}

	auto g = path.readJSON!(Game);
	g.path = path;
	return g;
}

void gamemenu(Game *game)
{
	int c = 0;
	do {
		switch(c) {
			case '\n':
				run(game);
				break;
			case 's':
				save_game(game);
				break;
			default: break;
		}
		wclear(statusbar);
		wprintw(statusbar,
				"ENTER: Start Run | S: Save Game | Q: Back to Main Menu");
		wrefresh(statusbar);
	} while((c = getch()) != 'q');
	if(game.dirty) {
		save_game(game);
	}
}

void read_string(WINDOW *w, ref string s)
{
	int c;
	while((c = wgetch(w)) != '\n') {
		wprintw(w, "%c", c);
		s ~= cast(char)c;
	}
}

void newgame()
{
	auto ng = new Game;
	{
		scope auto wins = create_window(12, col-1, row / 2 - 6, 1);
		scrollok(wins.main, true);
		refresh();
		mvwprintw(wins.b, 0, 2, "[New Game]");
		wrefresh(wins.b);
		wprintw(wins.main, "Enter a name: ");
		wrefresh(wins.main);
		read_string(wins.main, ng.name);
		wprintw(wins.main, "\n");

		while(true) {
			wprintw(wins.main, "Enter split name (blank to stop): ");
			string sn;
			wrefresh(wins.main);
			read_string(wins.main, sn);
			wprintw(wins.main, "\n");
			if(sn.length == 0)
				break;
			ng.splitnames ~= sn;
		}

		refresh();
	}
	save_game(ng);
	gamemenu(ng);
}

void main()
{
	initscr();
	curs_set(0);
	start_color();
	init_pair(1,COLOR_BLACK, COLOR_WHITE);
	init_pair(2,COLOR_YELLOW, COLOR_BLACK);
	init_pair(3,COLOR_GREEN, COLOR_BLACK);
	init_pair(4,COLOR_RED, COLOR_BLACK);
	refresh();
	noecho();
	cbreak();
	scrollok(stdscr, true);
	
	getmaxyx(stdscr, row, col);
	statusbar = newwin(1, col+1, row, 0);
	wbkgd(statusbar, COLOR_PAIR(1));

	int c = 0;
	do {
		switch(c) {
			case 'o':
				auto g = open_game();
				gamemenu(&g);
				break;
			case 'n':
				newgame();
				break;
			default: break;
		}
		wclear(statusbar);
		wprintw(statusbar, "O: Open Game | N: New Game | Q: Quit");
		wrefresh(statusbar);
	} while((c = getch()) != 'q');


	endwin();	
}

