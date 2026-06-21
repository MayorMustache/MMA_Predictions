# =============================================================================
# Web Scraper (Playwright version)
# =============================================================================
# Description: This script gathers the information regarding events and fighters.
#              Modified version of https://www.kaggle.com/datasets/neelagiriaditya/ufc-datasets-1994-2025
#              Adapted to use Playwright instead of requests, since ufcstats.com
#              now serves a JS proof-of-work anti-bot challenge that plain
#              requests/BeautifulSoup cannot pass.
#              Supports resuming: already-scraped events/fights/fighters are
#              skipped and new data is appended to existing CSV files.
#              Created with the use of Claude (Sonnet 4.6)
# Author:      Michael Schenk
# Date:        21.06.2026
# =============================================================================

# --- 1. Dependencies ----------------------------------------------------------

from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright
import pandas as pd
import numpy as np
import time
from pathlib import Path

# --- 2. Setup -----------------------------------------------------------------

DATA_DIR = Path("data/RawData").expanduser()
DATA_DIR.mkdir(parents=True, exist_ok=True)
print(f"Data folder: {DATA_DIR}")

# File paths
SCRAPED_EVENTS_PATH  = DATA_DIR / "scraped_events.csv"
EVENT_DETAILS_PATH   = DATA_DIR / "event_details.csv"
FIGHT_DETAILS_PATH   = DATA_DIR / "fight_details.csv"
FIGHTER_DETAILS_PATH = DATA_DIR / "fighter_details.csv"
UFC_PATH             = DATA_DIR / "UFC.csv"
UPCOMING_EVENTS_PATH = DATA_DIR / "upcoming_events.csv"

# In-memory accumulators for this run (new data only)
fight_details       = []
new_fight_links_all = []
winner_names        = []
fighter_detail_data = []

# --- 3. Resume state ----------------------------------------------------------
# Load already-scraped event URLs so we skip them this run.

if SCRAPED_EVENTS_PATH.exists():
    already_scraped_events = set(pd.read_csv(SCRAPED_EVENTS_PATH)["url"].tolist())
    print(f"Resuming: {len(already_scraped_events)} events already scraped.")
else:
    already_scraped_events = set()
    print("No previous scrape found — starting fresh.")

# Load already-scraped fight links so we skip them too.
if FIGHT_DETAILS_PATH.exists():
    already_scraped_fights = set(
        pd.read_csv(FIGHT_DETAILS_PATH, usecols=["fight_id"])["fight_id"].astype(str).tolist()
    )
    print(f"Resuming: {len(already_scraped_fights)} fights already scraped.")
else:
    already_scraped_fights = set()

# Load already-scraped fighter ids.
if FIGHTER_DETAILS_PATH.exists():
    already_scraped_fighters = set(
        pd.read_csv(FIGHTER_DETAILS_PATH, usecols=["id"])["id"].astype(str).tolist()
    )
    print(f"Resuming: {len(already_scraped_fighters)} fighters already scraped.")
else:
    already_scraped_fighters = set()

# --- 4. Helper ----------------------------------------------------------------

def get_rendered_html(page, url, wait_selector=None, timeout=30000):
    """
    Navigate to a URL using an existing Playwright page object and return
    the fully rendered HTML after any JS challenge has resolved.
    """
    page.goto(url, timeout=timeout)
    if wait_selector:
        page.wait_for_selector(wait_selector, timeout=timeout)
    else:
        page.wait_for_load_state("networkidle", timeout=timeout)
    return page.content()


# --- 5. Scraping the event list -----------------------------------------------

ufc_link = "http://ufcstats.com/statistics/events/completed?page=all"

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    context = browser.new_context(
        user_agent=(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        )
    )
    page = context.new_page()

    # -- 5a. Get all event links --
    html = get_rendered_html(
        page,
        ufc_link,
        wait_selector="a.b-link.b-link_style_black",
    )
    soup = BeautifulSoup(html, "lxml")
    event_links_soup = soup.find_all("a", class_="b-link b-link_style_black")
    event_links      = [link["href"] for link in event_links_soup]
    print(f"{len(event_links)} events found on site.")
    

    # Filter to only unscraped events
    events_to_scrape = [l for l in event_links if l not in already_scraped_events]
    print(f"{len(events_to_scrape)} new events to scrape.")

    # -- 5b. Scrape each new event page --
    def get_event_data(idx, link):
        """Scrape fight-level data from a single event page."""
        link = link.strip()
        html = get_rendered_html(
            page,
            link,
            wait_selector="tr.b-fight-details__table-row",
        )
        soup = BeautifulSoup(html, "lxml")

        event_id      = link[-16:]
        date_loc_list = soup.find_all("li", "b-list__box-list-item")
        date          = date_loc_list[0].text.replace("Date:", "").strip()
        location      = date_loc_list[1].text.replace("Location:", "").strip()

        fight_links = soup.find_all(
            "tr",
            class_="b-fight-details__table-row b-fight-details__table-row__hover js-fight-details-click",
        )

        for i in fight_links:
            winner_name = None
            winner_id   = None
            w_l_d       = i.find("i", class_="b-flag__text").text
            fight_id    = i["data-link"][-16:]

            if w_l_d == "win":
                players     = i.find("td", class_="b-fight-details__table-col l-page_align_left")
                players     = players.find_all("a", class_="b-link b-link_style_black")
                winner_name = players[0].text.strip()
                winner_id   = players[0]["href"][-16:]

            data_dic = {
                "event_id"  : event_id,
                "fight_id"  : fight_id,
                "date"      : date,
                "location"  : location,
                "winner"    : winner_name,
                "winner_id" : winner_id,
            }
            new_fight_links_all.append(i["data-link"])
            winner_names.append(data_dic)

        print(f"Scraped event: {link}  ({idx + 1} / {len(events_to_scrape)})")

    for idx, link in enumerate(events_to_scrape):
        try:
            get_event_data(idx, link)
            time.sleep(0.5)
        except Exception as e:
            print(f"Failed event: {link} — {e}")

    browser.close()

# -- 5c. Save / append event details --
if winner_names:
    df_winner_new = pd.DataFrame(data=winner_names)
    if EVENT_DETAILS_PATH.exists():
        df_winner = pd.concat(
            [pd.read_csv(EVENT_DETAILS_PATH), df_winner_new], ignore_index=True
        )
    else:
        df_winner = df_winner_new
    df_winner.to_csv(EVENT_DETAILS_PATH, index=False)
    print(f"event_details.csv updated: {len(df_winner)} total rows.")
else:
    # Load existing for use in merge later
    df_winner = pd.read_csv(EVENT_DETAILS_PATH) if EVENT_DETAILS_PATH.exists() else pd.DataFrame()
    print("No new event data — loaded existing event_details.csv.")

# Also load any fight links from prior runs that still need fight-level scraping.
# (fight links from events already scraped are already in fight_details.csv,
#  so we only need the new ones collected just now in new_fight_links_all.)

# --- 6. Scraping individual fight pages ----------------------------------------

# Filter to only fights not yet in fight_details.csv
fights_to_scrape = [
    l for l in new_fight_links_all
    if l.strip()[-16:] not in already_scraped_fights
]
print(f"{len(fights_to_scrape)} new fights to scrape.")

def get_fight_data(idx, link):
    """Scrape fight data from the given link."""
    link = link.strip()
    try:
        html = get_rendered_html(page, link, wait_selector="a.b-link")
        soup = BeautifulSoup(html, "lxml")

        event_name = soup.find('a', class_="b-link").text.strip()
        event_id   = soup.find('a', class_="b-link")['href'][-16:]
        fight_id   = link[-16:]

        fighter_nams = soup.find_all('a', class_='b-link b-fight-details__person-link')
        r_name = fighter_nams[0].text.strip()
        b_name = fighter_nams[1].text.strip()
        r_id   = fighter_nams[0]['href'].strip()[-16:]
        b_id   = fighter_nams[1]['href'].strip()[-16:]

        division_info  = soup.find('i', class_='b-fight-details__fight-title').text.lower()
        is_title_fight = 1 if 'title' in division_info else 0
        division_info  = division_info.replace('ufc', "").replace("title", "").replace("bout", "").strip()

        method = soup.find('i', style='font-style: normal').text.strip()

        p_tag              = soup.find('p', class_="b-fight-details__text")
        fight_details_list = p_tag.find_all('i', class_='b-fight-details__text-item')
        finish_round       = int(fight_details_list[0].text.lower().replace("round:", "").strip())
        ts                 = fight_details_list[1].text.lower().replace("time:", "").strip().split(":")
        match_time_sec     = int(ts[0]) * 60 + int(ts[-1])
        total_rounds       = fight_details_list[2].text.lower().replace("time format:", "").strip()
        total_rounds       = None if total_rounds == "no time limit" else int(total_rounds[0])
        referee            = fight_details_list[3].text.replace("Referee:", "").strip()

        tables = soup.find_all('table', style="width: 745px")

        if len(tables) > 0:
            td_1 = tables[0].find_all('td', class_='b-fight-details__table-col')

            kd               = td_1[1].text.split()
            r_kd, b_kd       = int(kd[0]), int(kd[1])

            ss               = td_1[2].text.split()
            r_sig_str_landed, r_sig_str_atmpted = int(ss[0]), int(ss[2])
            b_sig_str_landed, b_sig_str_atmpted = int(ss[3]), int(ss[5])

            ssa              = td_1[3].text.split()
            r_sig_str_acc    = int(ssa[0].replace("%","")) if ssa[0] != "---" else None
            b_sig_str_acc    = int(ssa[1].replace("%","")) if ssa[1] != "---" else None

            ts2              = td_1[4].text.split()
            r_total_str_landed, r_total_str_atmpted = int(ts2[0]), int(ts2[2])
            b_total_str_landed, b_total_str_atmpted = int(ts2[3]), int(ts2[5])

            def acc(l, a):
                try: return int(round(l / a, 2) * 100)
                except: return None

            r_total_str_acc = acc(r_total_str_landed, r_total_str_atmpted)
            b_total_str_acc = acc(b_total_str_landed, b_total_str_atmpted)

            td               = td_1[5].text.split()
            r_td_landed, r_td_atmpted = int(td[0]), int(td[2])
            b_td_landed, b_td_atmpted = int(td[3]), int(td[5])

            tda              = td_1[6].text.split()
            r_td_acc         = int(tda[0].replace("%","")) if tda[0] != "---" else None
            b_td_acc         = int(tda[1].replace("%","")) if tda[1] != "---" else None

            sa               = td_1[7].text.split()
            r_sub_att, b_sub_att = int(sa[0]), int(sa[1])

            ct               = td_1[9].text.split()
            rc = ct[0].split(":"); r_ctrl = int(rc[0])*60+int(rc[1]) if rc[0] != '--' else None
            bc = ct[1].split(":"); b_ctrl = int(bc[0])*60+int(bc[1]) if bc[0] != '--' else None

            td_2 = tables[1].find_all('td', class_='b-fight-details__table-col')

            def ps(i):
                v = td_2[i].text.split()
                return int(v[0]), int(v[2]), int(v[3]), int(v[5])

            r_head_landed,  r_head_atmpted,  b_head_landed,  b_head_atmpted  = ps(3)
            r_body_landed,  r_body_atmpted,  b_body_landed,  b_body_atmpted  = ps(4)
            r_leg_landed,   r_leg_atmpted,   b_leg_landed,   b_leg_atmpted   = ps(5)
            r_dist_landed,  r_dist_atmpted,  b_dist_landed,  b_dist_atmpted  = ps(6)
            r_clinch_landed,r_clinch_atmpted,b_clinch_landed,b_clinch_atmpted= ps(7)
            r_ground_landed,r_ground_atmpted,b_ground_landed,b_ground_atmpted= ps(8)

            r_head_acc=acc(r_head_landed,r_head_atmpted);   b_head_acc=acc(b_head_landed,b_head_atmpted)
            r_body_acc=acc(r_body_landed,r_body_atmpted);   b_body_acc=acc(b_body_landed,b_body_atmpted)
            r_leg_acc=acc(r_leg_landed,r_leg_atmpted);      b_leg_acc=acc(b_leg_landed,b_leg_atmpted)
            r_dist_acc=acc(r_dist_landed,r_dist_atmpted);   b_dist_acc=acc(b_dist_landed,b_dist_atmpted)
            r_clinch_acc=acc(r_clinch_landed,r_clinch_atmpted); b_clinch_acc=acc(b_clinch_landed,b_clinch_atmpted)
            r_ground_acc=acc(r_ground_landed,r_ground_atmpted); b_ground_acc=acc(b_ground_landed,b_ground_atmpted)
        else:
            r_kd=b_kd=r_sig_str_landed=b_sig_str_landed=r_sig_str_atmpted=b_sig_str_atmpted=None
            r_sig_str_acc=b_sig_str_acc=r_total_str_landed=b_total_str_landed=None
            r_total_str_atmpted=b_total_str_atmpted=r_total_str_acc=b_total_str_acc=None
            r_td_landed=b_td_landed=r_td_atmpted=b_td_atmpted=r_td_acc=b_td_acc=None
            r_sub_att=b_sub_att=r_ctrl=b_ctrl=None
            r_head_landed=b_head_landed=r_head_atmpted=b_head_atmpted=r_head_acc=b_head_acc=None
            r_body_landed=b_body_landed=r_body_atmpted=b_body_atmpted=r_body_acc=b_body_acc=None
            r_leg_landed=b_leg_landed=r_leg_atmpted=b_leg_atmpted=r_leg_acc=b_leg_acc=None
            r_dist_landed=b_dist_landed=r_dist_atmpted=b_dist_atmpted=r_dist_acc=b_dist_acc=None
            r_clinch_landed=b_clinch_landed=r_clinch_atmpted=b_clinch_atmpted=r_clinch_acc=b_clinch_acc=None
            r_ground_landed=b_ground_landed=r_ground_atmpted=b_ground_atmpted=r_ground_acc=b_ground_acc=None
            r_landed_head_per=b_landed_head_per=r_landed_dist_per=b_landed_dist_per=None
            r_landed_body_per=b_landed_body_per=r_landed_clinch_per=b_landed_clinch_per=None
            r_landed_leg_per=b_landed_leg_per=r_landed_ground_per=b_landed_ground_per=None

        try:
            rl=soup.find_all('i',class_="b-fight-details__charts-num b-fight-details__charts-num_style_red b-fight-details__charts-num_pos_left js-red")
            r_landed_head_per=int(rl[0].text.strip().replace("%","")); r_landed_dist_per=int(rl[1].text.strip().replace("%",""))
            bl=soup.find_all('i',class_="b-fight-details__charts-num b-fight-details__charts-num_style_blue b-fight-details__charts-num_pos_right js-blue")
            b_landed_head_per=int(bl[0].text.strip().replace("%","")); b_landed_dist_per=int(bl[1].text.strip().replace("%",""))
        except: r_landed_head_per=r_landed_dist_per=b_landed_head_per=b_landed_dist_per=None

        try:
            rl2=soup.find_all('i',class_="b-fight-details__charts-num b-fight-details__charts-num_style_dark-red b-fight-details__charts-num_pos_left js-red")
            r_landed_body_per=int(rl2[0].text.strip().replace("%","")); r_landed_clinch_per=int(rl2[1].text.strip().replace("%",""))
            bl2=soup.find_all('i',class_="b-fight-details__charts-num b-fight-details__charts-num_style_dark-blue b-fight-details__charts-num_pos_right js-blue")
            b_landed_body_per=int(bl2[0].text.strip().replace("%","")); b_landed_clinch_per=int(bl2[1].text.strip().replace("%",""))
        except: r_landed_body_per=r_landed_clinch_per=b_landed_body_per=b_landed_clinch_per=None

        try:
            rl3=soup.find_all('i',class_="b-fight-details__charts-num b-fight-details__charts-num_style_light-red b-fight-details__charts-num_pos_left js-red")
            r_landed_leg_per=int(rl3[0].text.strip().replace("%","")); r_landed_ground_per=int(rl3[1].text.strip().replace("%",""))
            bl3=soup.find_all('i',class_="b-fight-details__charts-num b-fight-details__charts-num_style_light-blue b-fight-details__charts-num_pos_right js-blue")
            b_landed_leg_per=int(bl3[0].text.strip().replace("%","")); b_landed_ground_per=int(bl3[1].text.strip().replace("%",""))
        except: r_landed_leg_per=r_landed_ground_per=b_landed_leg_per=b_landed_ground_per=None

        data_dic = {
            "event_name": event_name, "event_id": event_id, "fight_id": fight_id,
            "r_name": r_name, "r_id": r_id, "b_name": b_name, "b_id": b_id,
            "division": division_info, "title_fight": is_title_fight, "method": method,
            "finish_round": finish_round, "match_time_sec": match_time_sec,
            "total_rounds": total_rounds, "referee": referee,
            "r_kd": r_kd, "r_sig_str_landed": r_sig_str_landed, "r_sig_str_atmpted": r_sig_str_atmpted,
            "r_sig_str_acc": r_sig_str_acc, "r_total_str_landed": r_total_str_landed,
            "r_total_str_atmpted": r_total_str_atmpted, "r_total_str_acc": r_total_str_acc,
            "r_td_landed": r_td_landed, "r_td_atmpted": r_td_atmpted, "r_td_acc": r_td_acc,
            "r_sub_att": r_sub_att, "r_ctrl": r_ctrl,
            "r_head_landed": r_head_landed, "r_head_atmpted": r_head_atmpted, "r_head_acc": r_head_acc,
            "r_body_landed": r_body_landed, "r_body_atmpted": r_body_atmpted, "r_body_acc": r_body_acc,
            "r_leg_landed": r_leg_landed, "r_leg_atmpted": r_leg_atmpted, "r_leg_acc": r_leg_acc,
            "r_dist_landed": r_dist_landed, "r_dist_atmpted": r_dist_atmpted, "r_dist_acc": r_dist_acc,
            "r_clinch_landed": r_clinch_landed, "r_clinch_atmpted": r_clinch_atmpted, "r_clinch_acc": r_clinch_acc,
            "r_ground_landed": r_ground_landed, "r_ground_atmpted": r_ground_atmpted, "r_ground_acc": r_ground_acc,
            "r_landed_head_per": r_landed_head_per, "r_landed_body_per": r_landed_body_per,
            "r_landed_leg_per": r_landed_leg_per, "r_landed_dist_per": r_landed_dist_per,
            "r_landed_clinch_per": r_landed_clinch_per, "r_landed_ground_per": r_landed_ground_per,
            "b_kd": b_kd, "b_sig_str_landed": b_sig_str_landed, "b_sig_str_atmpted": b_sig_str_atmpted,
            "b_sig_str_acc": b_sig_str_acc, "b_total_str_landed": b_total_str_landed,
            "b_total_str_atmpted": b_total_str_atmpted, "b_total_str_acc": b_total_str_acc,
            "b_td_landed": b_td_landed, "b_td_atmpted": b_td_atmpted, "b_td_acc": b_td_acc,
            "b_sub_att": b_sub_att, "b_ctrl": b_ctrl,
            "b_head_landed": b_head_landed, "b_head_atmpted": b_head_atmpted, "b_head_acc": b_head_acc,
            "b_body_landed": b_body_landed, "b_body_atmpted": b_body_atmpted, "b_body_acc": b_body_acc,
            "b_leg_landed": b_leg_landed, "b_leg_atmpted": b_leg_atmpted, "b_leg_acc": b_leg_acc,
            "b_dist_landed": b_dist_landed, "b_dist_atmpted": b_dist_atmpted, "b_dist_acc": b_dist_acc,
            "b_clinch_landed": b_clinch_landed, "b_clinch_atmpted": b_clinch_atmpted, "b_clinch_acc": b_clinch_acc,
            "b_ground_landed": b_ground_landed, "b_ground_atmpted": b_ground_atmpted, "b_ground_acc": b_ground_acc,
            "b_landed_head_per": b_landed_head_per, "b_landed_body_per": b_landed_body_per,
            "b_landed_leg_per": b_landed_leg_per, "b_landed_dist_per": b_landed_dist_per,
            "b_landed_clinch_per": b_landed_clinch_per, "b_landed_ground_per": b_landed_ground_per,
        }
        fight_details.append(data_dic)
        print(f"Scraped fight {idx + 1}/{len(fights_to_scrape)}: {link}")

    except Exception as e:
        print(f"Failed fight: {link} — {e}")


with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    context = browser.new_context(
        user_agent=(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        )
    )
    page = context.new_page()

    for idx, link in enumerate(fights_to_scrape):
        try:
            get_fight_data(idx, link)
            time.sleep(0.5)
        except Exception as e:
            print(f"Failed fight: {link} — {e}")

    browser.close()

# Save / append fight details
if fight_details:
    df_fight_new = pd.DataFrame(data=fight_details)
    if FIGHT_DETAILS_PATH.exists():
        df_fight = pd.concat(
            [pd.read_csv(FIGHT_DETAILS_PATH), df_fight_new], ignore_index=True
        )
    else:
        df_fight = df_fight_new
    df_fight.to_csv(FIGHT_DETAILS_PATH, index=False)
    print(f"fight_details.csv updated: {len(df_fight)} total rows.")
else:
    df_fight = pd.read_csv(FIGHT_DETAILS_PATH) if FIGHT_DETAILS_PATH.exists() else pd.DataFrame()
    print("No new fight data — loaded existing fight_details.csv.")

# --- 7. Scraping fighter details -----------------------------------------------

r_fighter_id = df_fight['r_id'].unique()
b_fighter_id = df_fight['b_id'].unique()
all_ids      = list(set(list(r_fighter_id) + list(b_fighter_id)))

# Filter to only fighters not yet scraped
fighters_to_scrape = [fid for fid in all_ids if str(fid) not in already_scraped_fighters]
print(f"{len(fighters_to_scrape)} new fighters to scrape.")

base_url = "http://ufcstats.com/fighter-details/"

def get_fighter_data(idx, fighter_id):
    """Scrape fighter data from the given fighter id."""
    try:
        html = get_rendered_html(
            page,
            base_url + fighter_id,
            wait_selector="span.b-content__title-highlight",
        )
        soup = BeautifulSoup(html, "lxml")

        fighter_name      = soup.find('span', class_='b-content__title-highlight').text.strip()
        fighter_nick_name = soup.find('p', class_="b-content__Nickname").text.strip()

        fighter_record = soup.find('span', class_="b-content__title-record").text.replace("Record:", "").strip().split('-')
        fighter_wins   = int(fighter_record[0].split()[0])
        fighter_losses = int(fighter_record[1].split()[0])
        fighter_draws  = int(fighter_record[2].split()[0])

        detail_list = soup.find_all('li', class_="b-list__box-list-item b-list__box-list-item_type_block")

        try:
            height = detail_list[0].text.replace("Height:", "").strip().replace("'", "").replace('"', '').split()
            height = round((int(height[0]) * 12 + int(height[1])) * 2.54, 2)
        except: height = None

        try:
            weight = round(float(detail_list[1].text.replace("Weight:", "").strip().replace(" lbs", "")) * 0.45359237, 2)
        except: weight = None

        try:
            reach = round(int(detail_list[2].text.replace("Reach:", "").strip().replace('"', "")) * 2.54, 2)
        except: reach = None

        try:
            stance = detail_list[3].text.replace("STANCE:", "").strip() or None
        except: stance = None

        try:
            dob = detail_list[4].text.replace("DOB:", "").strip()
            dob = dob if dob != "--" else None
        except: dob = None

        splm    = float(detail_list[5].text.replace("SLpM:", "").strip())
        str_acc = int(detail_list[6].text.replace("Str. Acc.:", "").strip().replace("%", ""))
        sapm    = float(detail_list[7].text.replace("SApM:", "").strip())
        str_def = int(detail_list[8].text.replace("Str. Def:", "").strip().replace("%", ""))
        td_avg  = float(detail_list[10].text.replace("TD Avg.:", "").strip())
        td_acc  = int(detail_list[11].text.replace("TD Acc.:", "").strip().replace("%", ""))
        td_def  = int(detail_list[12].text.replace("TD Def.:", "").strip().replace("%", ""))
        sub_avg = float(detail_list[13].text.replace("Sub. Avg.:", "").strip())

        data_dic = {
            "id": fighter_id, "name": fighter_name, "nick_name": fighter_nick_name,
            "wins": fighter_wins, "losses": fighter_losses, "draws": fighter_draws,
            "height": height, "weight": weight, "reach": reach, "stance": stance, "dob": dob,
            "splm": splm, "str_acc": str_acc, "sapm": sapm, "str_def": str_def,
            "td_avg": td_avg, "td_avg_acc": td_acc, "td_def": td_def, "sub_avg": sub_avg,
        }
        fighter_detail_data.append(data_dic)
        print(f"Scraped fighter {idx + 1}/{len(fighters_to_scrape)}: {fighter_name}")

    except Exception as e:
        print(f"Cannot process {base_url + fighter_id}. Skipping. ({e})")


with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    context = browser.new_context(
        user_agent=(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        )
    )
    page = context.new_page()

    for idx, fighter_id in enumerate(fighters_to_scrape):
        try:
            get_fighter_data(idx, fighter_id)
            time.sleep(0.5)
        except Exception as e:
            print(f"Failed fighter: {fighter_id} — {e}")

    browser.close()

# Save / append fighter details
if fighter_detail_data:
    df_fighter_new = pd.DataFrame(data=fighter_detail_data)
    if FIGHTER_DETAILS_PATH.exists():
        df_fighter = pd.concat(
            [pd.read_csv(FIGHTER_DETAILS_PATH), df_fighter_new], ignore_index=True
        )
    else:
        df_fighter = df_fighter_new
    df_fighter.to_csv(FIGHTER_DETAILS_PATH, index=False)
    print(f"fighter_details.csv updated: {len(df_fighter)} total rows.")
else:
    df_fighter = pd.read_csv(FIGHTER_DETAILS_PATH) if FIGHTER_DETAILS_PATH.exists() else pd.DataFrame()
    print("No new fighter data — loaded existing fighter_details.csv.")

# --- 8. Merging all data -------------------------------------------------------

df_merger_winners     = df_winner.drop(columns=['event_id']).copy()
df_fight              = df_fight.merge(right=df_merger_winners, on='fight_id')

df_fighter_renamed__r = df_fighter.add_prefix('r_').drop(columns=['r_name'])
df_fighter_renamed__b = df_fighter.add_prefix('b_').drop(columns=['b_name'])
df_fight              = df_fight.merge(right=df_fighter_renamed__r, on='r_id')
df_fight              = df_fight.merge(right=df_fighter_renamed__b, on='b_id')

cols = df_fight.columns
r_cols = [col for col in cols if col.startswith('r_')]
b_cols = [col for col in cols if col.startswith('b_')]

re_ordered_cols = [
    'event_id', 'event_name', 'date', 'location', 'fight_id',
    'division', 'title_fight', 'method', 'finish_round',
    'match_time_sec', 'total_rounds', 'referee',
] + r_cols + b_cols + ['winner', 'winner_id']

df_fight = df_fight[re_ordered_cols]

df_fight['date']  = pd.to_datetime(df_fight['date']).dt.strftime("%Y/%m/%d")
df_fight['r_dob'] = pd.to_datetime(df_fight['r_dob']).dt.strftime("%Y/%m/%d")
df_fight['b_dob'] = pd.to_datetime(df_fight['b_dob']).dt.strftime("%Y/%m/%d")

df_fight.to_csv(UFC_PATH, index=False)
print(f"Final dataset saved: {len(df_fight)} rows → {UFC_PATH}")

# --- 9. Save scraped event URLs -----------------------------------------------

all_scraped = already_scraped_events | set(events_to_scrape)
pd.DataFrame(sorted(all_scraped), columns=["url"]).to_csv(SCRAPED_EVENTS_PATH, index=False)
print(f"scraped_events.csv updated: {len(all_scraped)} events logged.")

# --- 10. Scraping upcoming events ---------------------------------------------
# We always re-scrape upcoming events so the CSV stays current.
# For each event we visit the event detail page to get the full fight card:
# fighter names/IDs, division, and whether it's a title fight.

upcoming_link = "http://ufcstats.com/statistics/events/upcoming?page=all"
upcoming_data = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    context = browser.new_context(
        user_agent=(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        )
    )
    page = context.new_page()

    # -- 10a. Get list of upcoming events --
    html = get_rendered_html(
        page,
        upcoming_link,
        wait_selector="a.b-link.b-link_style_black",
    )
    soup = BeautifulSoup(html, "lxml")

    # Collect event-level info from the listing page
    upcoming_events = []
    rows = soup.find_all("tr", class_="b-statistics__table-row")
    for row in rows:
        name_tag = row.find("a", class_="b-link b-link_style_black")
        if not name_tag:
            continue
        cols_td = row.find_all("td")
        if len(cols_td) < 2:
            continue

        event_name = name_tag.text.strip()
        event_url  = name_tag["href"]
        event_id   = event_url[-16:]
        date_span  = cols_td[0].find("span")
        date       = date_span.text.strip() if date_span else cols_td[0].text.strip()
        location   = cols_td[1].text.strip()

        upcoming_events.append({
            "event_id"   : event_id,
            "event_name" : event_name,
            "date"       : date,
            "location"   : location,
            "url"        : event_url,
        })

    print(f"{len(upcoming_events)} upcoming events found.")

    # -- 10b. Visit each event detail page to get the full fight card --
    for ev in upcoming_events:
        try:
            html = get_rendered_html(
                page,
                ev["url"],
                wait_selector="tr.b-fight-details__table-row",
            )
            soup = BeautifulSoup(html, "lxml")

            fight_rows = soup.find_all(
                "tr",
                class_="b-fight-details__table-row b-fight-details__table-row__hover js-fight-details-click",
            )

            for fight_row in fight_rows:
                # Fighter names & IDs
                fighter_links = fight_row.find_all("a", class_="b-link b-link_style_black")
                if len(fighter_links) < 2:
                    continue
                r_name = fighter_links[0].text.strip()
                r_id   = fighter_links[0]["href"][-16:]
                b_name = fighter_links[1].text.strip()
                b_id   = fighter_links[1]["href"][-16:]

                # Fight link / ID
                fight_url = fight_row.get("data-link", "")
                fight_id  = fight_url[-16:] if fight_url else None

                # All <td> columns in the row
                # Layout: 0=fighters, 1=KD, 2=Str, 3=Td, 4=Sub, 5=Weight class, 6=Method, 7=Round, 8=Time
                tds = fight_row.find_all("td", class_="b-fight-details__table-col")

                def td_text(idx):
                    try: return tds[idx].text.strip()
                    except: return None

                # Weight class / division & title fight
                weight_class_raw = td_text(5) or ""
                is_title_fight   = 1 if "title" in weight_class_raw.lower() else 0
                division         = (
                    weight_class_raw.lower()
                    .replace("ufc", "").replace("title", "").replace("bout", "").strip()
                )

                # Method (often blank for upcoming)
                method = td_text(6)
                method = None if not method or method == "--" else method

                # Scheduled rounds
                try:    scheduled_rounds = int(td_text(7))
                except: scheduled_rounds = None

                # Time format per round
                time_format = td_text(8)
                time_format = None if not time_format or time_format == "--" else time_format

                upcoming_data.append({
                    "event_id"        : ev["event_id"],
                    "event_name"      : ev["event_name"],
                    "date"            : ev["date"],
                    "location"        : ev["location"],
                    "fight_id"        : fight_id,
                    "fight_url"       : fight_url,
                    "r_name"          : r_name,
                    "r_id"            : r_id,
                    "b_name"          : b_name,
                    "b_id"            : b_id,
                    "division"        : division,
                    "title_fight"     : is_title_fight,
                    "method"          : method,
                    "scheduled_rounds": scheduled_rounds,
                    "time_format"     : time_format,
                })

            print(f"Scraped fight card: {ev['event_name']} ({len(fight_rows)} bouts)")
            time.sleep(0.5)

        except Exception as e:
            print(f"Failed upcoming event: {ev['event_name']} — {e}")

    browser.close()

df_upcoming = pd.DataFrame(data=upcoming_data)
df_upcoming.to_csv(UPCOMING_EVENTS_PATH, index=False)
print(f"upcoming_events.csv saved: {len(df_upcoming)} bouts across {len(upcoming_events)} events → {UPCOMING_EVENTS_PATH}")
