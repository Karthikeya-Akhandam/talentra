import glob
import re

tables = []
fks = []
pks = []
uniques = []
checks = []
excludes = []
triggers = []
columns_count = 0

table_details = {}

for f in sorted(glob.glob("schema/*.sql")):
    content = open(f, encoding="utf-8").read()
    # Find tables
    t_matches = re.findall(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_\.]+)", content, re.IGNORECASE)
    for t in t_matches:
        if t not in tables:
            tables.append(t)
    
    # Count columns roughly by lines inside CREATE TABLE
    table_blocks = re.findall(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_\.]+)\s*\((.*?)\);", content, re.DOTALL | re.IGNORECASE)
    for tname, block in table_blocks:
        lines = [line.strip() for line in block.split("\n") if line.strip() and not line.strip().startswith("--")]
        # filter out constraint lines
        col_lines = [l for l in lines if not re.match(r"^(CONSTRAINT|PRIMARY\s+KEY|FOREIGN\s+KEY|UNIQUE|CHECK|EXCLUDE)", l, re.IGNORECASE)]
        table_details[tname] = len(col_lines)
        columns_count += len(col_lines)
        
    fks.extend(re.findall(r"FOREIGN\s+KEY", content, re.IGNORECASE))
    pks.extend(re.findall(r"PRIMARY\s+KEY", content, re.IGNORECASE))
    uniques.extend(re.findall(r"\bUNIQUE\b", content, re.IGNORECASE))
    checks.extend(re.findall(r"\bCHECK\s*\(", content, re.IGNORECASE))
    excludes.extend(re.findall(r"EXCLUDE\s+USING", content, re.IGNORECASE))
    triggers.extend(re.findall(r"CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER", content, re.IGNORECASE))

print("=== TALENTRA DATABASE STATISTICS ===")
print(f"Total Tables Created: {len(tables)}")
print(f"Total Columns Defined: {columns_count}")
print(f"Foreign Key Relationships: {len(fks)}")
print(f"Primary Keys: {len(pks)}")
print(f"Unique Constraints: {len(uniques)}")
print(f"CHECK Constraints: {len(checks)}")
print(f"GiST Exclusion Constraints: {len(excludes)}")
print(f"Database Integrity Triggers: {len(triggers)}")
print("\nTables list:")
for t, c in table_details.items():
    print(f"- {t}: {c} columns")
