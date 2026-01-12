Congressional Data Vector Building 108-118th Congresses
Lizzie Tucker under the guidance of Prof. Wendy Tam
Vanderbilt University
Last Updated January 11, 2026

This generates chamber, cosponsors, sponsors, and years vectors for every bill within Congress from the 108th to the 118th Congresses. It builds off of the data collected within the commonly-relied-upon congress GitHub, seen here: https://github.com/unitedstates/congress/wiki/bills. This is where all underlying bill data came from.

ROADMAP FOR INTERACTING WITH THIS REPO:
This repo uses branches as a form of version control to facilitate easy cloning and use of data and ensure that you're not cloning more than you want to. The following branches are available, please clone the one most relevant to your work. Check the README.md for each branch for more information about that branch's resources.

main
   - This is the branch we're on currently, it includes the base data that all of the branches have access to, which is supposed to be all the bills from congresses 108-118. The main work for this branch is done within build_global_vecs.ps1, which builds 4 vectors, chamber, cosponsors, sponsors, and years, which are aligned one bill per line. These are built from the per-congress CSV's I created within each congress's folder with the naming convention sponsors_by_icpsr_id_CONGRESSNUMBER.csv. You'll find these are very helpful. 
   - A few callouts here: in processing this data, it seems that a few files got corrupted in my initial download, please follow step 1 below to remedy this on any branch you enter (it's good practice to do step one no matter what). Additionally, PLEASE note if you're used to working with older congressional data that had congresspeople's names identified by thomas_id, the government stopped assigning thomas_ids around 2016, so within the build_global_vecs.ps1 from there, ICPSRid to name was used instead (in line with Prof. Tam's previous research).

party_icpsr_sheets
   - This includes everything that main does, but with party tracking for each sponsor based on their party at the time they sponsored or cosponsored a bill. This party tracking is done within vectors that mirror the sponsors and cosponsors vectors, with the congressperson's party (D, R, or I) in place of their ICPSR id. This is useful for figuring out anything to do with bipartisanship data.
   - This also adds dated to the bills within their sponsors_by_icpsr_id_CONGRESSNUMBER.csv, stating the date the bill was introduced at. This date is used to calculate a congressperson's party at time of sponsorship.

data_significance
- This includes everything that main and party_icpsr_sheets do, but with the addition of data processing within the updated_housesw.Rmd and updated_senatesw.Rmd. Please see these files for more description of the data processing they do. 
- Additionally, this includes a bill_congress.vec, bill_id.vec, and bill_type.vec, all of which are built within the Rmds listed above for use within the Rmds listed above. 
- This branch also adds significance_encodings for each bill from the 108th to 118th congress, which are curteosy of the Center for Effective Lawmaking and were used in calculating their Legislative Effectiveness scores. These are used as a dependent variable within the Rmds to the independent variables of cosponsor bipartisanship scores and more.

Recommendations for further data work:
1. Transition the logic within build_global_vecs.ps1 and the main key for congresspeople from being identified by ICPSR id to being identified by bioguide id. This lines up more with how legislators are already stored in the raw bill data jsons, and it also helps avoid the ICPSR id lag that happens when a legislator is newer. This would certainly be an undertaking, with work both on this branch and especially on the party_icpsr_sheets branch, but it would improve this repo as a whole.
2. As stated above, fill in the (very few, but existent and powerful) data gaps within the bills by re-running the data fetcher listed in step 1 Instructions to collect data below. This will improve the findings for cosponsor bipartisanship in the Rmd's you will find on the data_significance branch above. 
3. Someone who knows how to do statistical analysis, please take my data and work finding cosponsor bipartisanship scores (found in the updated_housesw.Rmd and updated_senatesw.Rmd on the data_significance branch above) and interpret them. Unfortunately, this is out of my wheelhouse for my current timeline, but this could be very revealing.
4. Use the icpsr_house_cheatsheet.csv and the icpsr_senate_cheatsheet.csv found on both the data_significance_branch and the party_icpsr_sheets branch to create some really cool congressional visualizations including names for cosponsorships. I wanted to get to this, but I don't know much about Gephi and graphing with R, and I know someone else could do a better job with my data than I could at this.

Instructions to collect data with this current setup:
1. First, if more recent data than the 118th congress is needed, follow the directions in the following GitHub to collect the bills and their sponsors, cosponsors, year, chamber, and more. This was the data source I used, and yes it will take a while to both collect all the data then process it as bills. I do not recommend doing this step UNLESS you need data from the 119th congress or are checking my work, which is always good practice! Here's the GitHub: https://github.com/unitedstates/congress/wiki/bills
2. Please make sure the legislators data is updated if you're doing data from the 119th congress onward--
   the current legislators data is under the legislators > legislators-current.yaml, which is automatically
   used to build a legislator identification map later. To update this map, simply download the most recent legislators-current.yaml from this GitHub: https://github.com/unitedstates/congress-legislators
2. Then, to make the vectors, run build_global_vecs.ps1. This will auto-recognize congressional
   folders through their bills subfolder. This automatically creates the chamber, cosponsors, sponsors, and years vectors for all bills from the 108th through the 118th congresses--correlated bill-wise by line in the vector. This also creates csvs within each congress's folder with the information needed to make these vectors, which is helpful because these csvs translate legislators identified by their bioguide or thomas id into their ICPSR id.