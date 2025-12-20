Congressional Data Vector Building 108-118th Congresses: party_icpsr_sheets branch

In addition to the below, which all happens on the main branch, this branch creates ICPSR cheatsheets for all
congresspeople appearing in the sponsor and cosponsor vectors for the house and senate. These cheatsheets
include that congressperson's ICPSR id, name in LASTNAME, FIRSTINITIAL. MIDDLEINITIAL. format, birthyear, and
gender. This also creates sponsor_party.vec and cosponsors_party.vec, which map 1:1 to the sponsor and cosponsors
vectors once those vectors have their first line trimmed. This identifies the party of that congressperson at the
time of that bill's introduction encoded as D, R, or I for democrat, republican, and independent.

This generates chamber, cosponsors, sponsors, and years vectors for every bill within Congress from the 108th to the 118th Congresses. It builds off of the data collected within the commonly-relied-upon congress GitHub, seen here: https://github.com/unitedstates/congress/wiki/bills. This is where all underlying bill data came from.

Instructions to collect data with this current setup:
1. First, if more recent data than the 118th congress is needed, follow the directions in the following GitHub to collect the bills and their sponsors, cosponsors, year, chamber, and more. This was the data source I used, and yes it will take a while to both collect all the data then process it as bills. I do not recommend doing this step UNLESS you need data from the 119th congress or are checking my work, which is always good practice! Here's the GitHub: https://github.com/unitedstates/congress/wiki/bills
2. Please make sure the legislators data is updated if you're doing data from the 119th congress onward--
   the current legislators data is under the legislators > legislators-current.yaml, which is automatically
   used to build a legislator identification map later. To update this map, simply download the most recent legislators-current.yaml from this GitHub: https://github.com/unitedstates/congress-legislators
2. Then, to make the vectors, run build_global_vecs.ps1. This will auto-recognize congressional
   folders through their bills subfolder. This automatically creates the chamber, cosponsors, sponsors, and years vectors for all bills from the 108th through the 118th congresses--correlated bill-wise by line in the vector. This also creates csvs within each congress's folder with the information needed to make these vectors, which is helpful because these csvs translate legislators identified by their bioguide or thomas id into their ICPSR id.