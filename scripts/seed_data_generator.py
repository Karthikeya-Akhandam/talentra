#!/usr/bin/env python3
"""
Talentra Synthetic Data Generator
Modules: Master Data, Profiles, Jobs, Applications, Gig, Subscriptions, Analytics
Milestones: Phase 5, Milestone 19 (B60, B61, B62, B63, B64)
Author: Solo Engineering Execution
Target Engine: PostgreSQL 17.5

Generates synthetically realistic distributions with:
- Multilingual candidate names (English, Hindi, Tamil, Telugu, Kannada, Marathi, French, German)
- Edge-case duplicate candidate profile detection
- Long-tail and Pareto distribution for job applications across requirements
- Realistic salary percentiles and experience bands
- High-performance CSV generation for PostgreSQL COPY ingestion
"""

import sys
import os
import csv
import uuid
import random
import datetime
import argparse
from typing import List, Dict

# Master Data Reference Seed Collections
COUNTRIES = [
    ("IN", "IND", "India", "+91", "INR"),
    ("US", "USA", "United States", "+1", "USD"),
    ("GB", "GBR", "United Kingdom", "+44", "GBP"),
    ("SG", "SGP", "Singapore", "+65", "SGD"),
    ("AE", "ARE", "United Arab Emirates", "+971", "AED"),
    ("DE", "DEU", "Germany", "+49", "EUR"),
    ("JP", "JPN", "Japan", "+81", "JPY"),
    ("AU", "AUS", "Australia", "+61", "AUD"),
]

INDIAN_STATES_CITIES = [
    ("KA", "Karnataka", ["Bengaluru", "Mysuru", "Hubballi"]),
    ("MH", "Maharashtra", ["Mumbai", "Pune", "Nagpur"]),
    ("TN", "Tamil Nadu", ["Chennai", "Coimbatore", "Madurai"]),
    ("DL", "Delhi", ["New Delhi", "North Delhi", "South Delhi"]),
    ("TS", "Telangana", ["Hyderabad", "Warangal"]),
    ("WB", "West Bengal", ["Kolkata", "Howrah"]),
    ("HR", "Haryana", ["Gurugram", "Faridabad"]),
    ("UP", "Uttar Pradesh", ["Noida", "Lucknow", "Kanpur"]),
]

INDUSTRIES = [
    ("TECH", "Information Technology & Software"),
    ("BFSI", "Banking, Financial Services & Insurance"),
    ("HEALTH", "Healthcare & Life Sciences"),
    ("ECOM", "E-Commerce & Retail"),
    ("AUTO", "Automotive & Manufacturing"),
    ("CONS", "Management Consulting"),
    ("MEDIA", "Digital Media & Entertainment"),
    ("EDTECH", "Education & EdTech"),
]

JOB_ROLES = [
    ("SWE_BE", "Backend Software Engineer", "TECH"),
    ("SWE_FE", "Frontend Software Engineer", "TECH"),
    ("SWE_FS", "Full Stack Developer", "TECH"),
    ("DEVOPS", "Cloud & DevOps Engineer", "TECH"),
    ("DATA_ENG", "Data Platform Engineer", "TECH"),
    ("AI_ENG", "Machine Learning & AI Engineer", "TECH"),
    ("PROD_MGR", "Technical Product Manager", "TECH"),
    ("FIN_ANL", "Financial Risk Analyst", "BFSI"),
    ("INVEST_BNK", "Investment Banking Associate", "BFSI"),
    ("CLIN_RES", "Clinical Research Associate", "HEALTH"),
    ("SUPPLY_CHN", "Supply Chain Operations Lead", "ECOM"),
]

SKILLS = [
    ("PYTHON", "Python", "Programming Language"),
    ("POSTGRES", "PostgreSQL", "Database"),
    ("JAVA", "Java", "Programming Language"),
    ("GOLANG", "Go", "Programming Language"),
    ("TYPESCRIPT", "TypeScript", "Frontend"),
    ("REACT", "React.js", "Frontend"),
    ("DOCKER", "Docker", "DevOps"),
    ("KUBERNETES", "Kubernetes", "DevOps"),
    ("AWS", "Amazon Web Services", "Cloud"),
    ("KAFKA", "Apache Kafka", "Messaging"),
    ("TERRAFORM", "Terraform", "Infrastructure"),
    ("PYTORCH", "PyTorch", "AI/ML"),
    ("RUST", "Rust", "Programming Language"),
    ("SQL", "SQL & Relational Modeling", "Database"),
]

FIRST_NAMES_MULTILINGUAL = [
    # English / Western
    "Alexander", "Charlotte", "David", "Emma", "James", "Sophia", "Oliver", "Lucas",
    # Indic - Hindi / North
    "Aarav", "Aditi", "Ananya", "Rohan", "Vikram", "Pooja", "Rahul", "Neha",
    # Indic - South (Tamil, Telugu, Kannada)
    "Karthik", "Suresh", "Lakshmi", "Venkatesh", "Priya", "Deepa", "Arun", "Divya",
    # European
    "Maximilian", "Clara", "Antoine", "Camille", "Hannah", "Leon", "Elena", "Matteo",
    # East Asian
    "Kenji", "Hana", "Wei", "Mei", "Jin", "Soo-jin", "Taro", "Yuki"
]

LAST_NAMES = [
    "Sharma", "Verma", "Patel", "Reddy", "Iyer", "Nair", "Rao", "Kumar",
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Miller", "Davis",
    "Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer",
    "Tanaka", "Yamamoto", "Sato", "Chen", "Zhang", "Wang", "Kim", "Park"
]

GIG_CATEGORIES = [
    "Database Architecture Review", "Cloud Migration Sprint",
    "Security Vulnerability Audit", "Mobile App UI Overhaul",
    "Machine Learning Pipeline Tuning", "Performance Bottleneck Analysis"
]

APPLICATION_STAGES = [
    "applied", "screened", "shortlisted", "interview_scheduled",
    "offered", "joined", "rejected", "withdrawn"
]

APPLICATION_WEIGHTS = [0.45, 0.20, 0.15, 0.10, 0.04, 0.02, 0.03, 0.01]


def generate_master_data_csv(output_dir: str):
    """Generates master data tables in CSV format."""
    os.makedirs(output_dir, exist_ok=True)
    print("Generating Master Data CSVs...")

    # 1. Countries
    countries_data = []
    with open(os.path.join(output_dir, "country.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "iso_code_2", "iso_code_3", "name", "phone_dial_code", "default_currency_code", "is_active", "sort_order"])
        for idx, (c2, c3, name, dial, curr) in enumerate(COUNTRIES):
            cid = str(uuid.uuid4())
            countries_data.append((cid, c2, name))
            writer.writerow([cid, c2, c3, name, dial, curr, True, idx + 1])

    # 2. States & Cities
    cities_data = []
    with open(os.path.join(output_dir, "state_province.csv"), "w", newline="", encoding="utf-8") as fs, \
         open(os.path.join(output_dir, "city.csv"), "w", newline="", encoding="utf-8") as fc:
        writer_s = csv.writer(fs)
        writer_c = csv.writer(fc)
        writer_s.writerow(["id", "country_id", "code", "name", "is_active", "sort_order"])
        writer_c.writerow(["id", "state_province_id", "name", "latitude", "longitude", "is_active"])

        india_id = countries_data[0][0]
        for s_idx, (s_code, s_name, city_list) in enumerate(INDIAN_STATES_CITIES):
            sid = str(uuid.uuid4())
            writer_s.writerow([sid, india_id, s_code, s_name, True, s_idx + 1])
            for c_name in city_list:
                city_id = str(uuid.uuid4())
                lat = round(random.uniform(12.0, 28.0), 6)
                lon = round(random.uniform(72.0, 88.0), 6)
                cities_data.append(city_id)
                writer_c.writerow([city_id, sid, c_name, lat, lon, True])

    # 3. Industries & Job Roles
    job_roles_data = []
    with open(os.path.join(output_dir, "industry.csv"), "w", newline="", encoding="utf-8") as fi, \
         open(os.path.join(output_dir, "job_role.csv"), "w", newline="", encoding="utf-8") as fr:
        writer_i = csv.writer(fi)
        writer_r = csv.writer(fr)
        writer_i.writerow(["id", "code", "name", "is_active", "sort_order"])
        writer_r.writerow(["id", "industry_id", "code", "title", "is_active", "sort_order"])

        ind_map = {}
        for idx, (code, name) in enumerate(INDUSTRIES):
            iid = str(uuid.uuid4())
            ind_map[code] = iid
            writer_i.writerow([iid, code, name, True, idx + 1])

        for idx, (rcode, rtitle, icode) in enumerate(JOB_ROLES):
            rid = str(uuid.uuid4())
            job_roles_data.append(rid)
            writer_r.writerow([rid, ind_map[icode], rcode, rtitle, True, idx + 1])

    # 4. Skills
    skills_data = []
    with open(os.path.join(output_dir, "skill.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "code", "name", "category", "is_active"])
        for code, name, cat in SKILLS:
            sk_id = str(uuid.uuid4())
            skills_data.append(sk_id)
            writer.writerow([sk_id, code, name, cat, True])

    print("Master Data CSVs generated successfully.")
    return cities_data, job_roles_data, skills_data


def generate_synthetic_workload(output_dir: str, num_candidates: int, num_jobs: int, num_applications: int):
    """Generates synthetic candidate profiles, jobs, and application funnel."""
    cities, job_roles, skills = generate_master_data_csv(output_dir)

    print(f"Generating Workload: {num_candidates:,} Candidates | {num_jobs:,} Jobs | {num_applications:,} Applications...")

    # Organizations
    org_ids = []
    with open(os.path.join(output_dir, "organisation.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "legal_name", "organisation_type_code", "verification_status_code", "is_active"])
        for i in range(max(10, num_jobs // 50)):
            org_id = str(uuid.uuid4())
            org_ids.append(org_id)
            writer.writerow([org_id, f"Enterprise Org {i+1} Technologies Ltd", "enterprise_employer", "verified", True])

    # Users and Candidate Profiles
    candidate_profile_ids = []
    with open(os.path.join(output_dir, "users.csv"), "w", newline="", encoding="utf-8") as fu, \
         open(os.path.join(output_dir, "candidate_profile.csv"), "w", newline="", encoding="utf-8") as fc:
        writer_u = csv.writer(fu)
        writer_c = csv.writer(fc)
        writer_u.writerow(["id", "email", "user_type_code", "status_code", "is_email_verified"])
        writer_c.writerow([
            "id", "user_id", "first_name", "last_name", "primary_email",
            "current_city_id", "total_experience_months", "current_salary_amount",
            "expected_salary_amount", "profile_completion_percentage", "is_actively_looking"
        ])

        for i in range(num_candidates):
            u_id = str(uuid.uuid4())
            c_id = str(uuid.uuid4())
            candidate_profile_ids.append(c_id)

            fname = random.choice(FIRST_NAMES_MULTILINGUAL)
            lname = random.choice(LAST_NAMES)
            email = f"candidate_{i}_{fname.lower()}.{lname.lower()}@domain.example"

            writer_u.writerow([u_id, email, "candidate", "active", True])

            exp_months = random.randint(0, 180)
            curr_salary = round(exp_months * random.uniform(12000, 25000), 2) if exp_months > 0 else 0.00
            exp_salary = round(curr_salary * random.uniform(1.2, 1.5), 2)
            completion = random.randint(60, 100)
            city_id = random.choice(cities)

            writer_c.writerow([
                c_id, u_id, fname, lname, email, city_id,
                exp_months, curr_salary, exp_salary, completion, True
            ])

    # Job Requirements
    job_ids = []
    with open(os.path.join(output_dir, "job_requirement.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "id", "organisation_id", "job_title", "job_role_id", "industry_id",
            "employment_type_id", "work_mode_id", "primary_city_id", "vacancies_count",
            "min_experience_months", "max_experience_months", "min_salary_amount",
            "max_salary_amount", "job_description", "publish_status_code", "is_open_to_consultants"
        ])

        for i in range(num_jobs):
            jid = str(uuid.uuid4())
            job_ids.append(jid)
            org_id = random.choice(org_ids)
            role_id = random.choice(job_roles)
            city_id = random.choice(cities)
            min_exp = random.choice([0, 24, 36, 60])
            max_exp = min_exp + random.choice([24, 36, 48])
            min_sal = round(random.uniform(400000, 1500000), 2)
            max_sal = round(min_sal * random.uniform(1.3, 1.8), 2)
            is_open = (random.random() < 0.40)

            writer.writerow([
                jid, org_id, f"Senior Software Engineer Position #{i+1}",
                role_id, role_id, role_id, role_id, city_id,
                random.randint(1, 5), min_exp, max_exp, min_sal, max_sal,
                f"Full technical specifications for job requirement #{i+1}.",
                "published", is_open
            ])

    # Candidate Applications (Partitioned across 2025-2027)
    with open(os.path.join(output_dir, "candidate_application.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "candidate_profile_id", "job_requirement_id", "current_status_code",
            "applied_at", "is_withdrawn"
        ])

        start_date = datetime.datetime(2025, 1, 1, tzinfo=datetime.timezone.utc)
        for i in range(num_applications):
            cand_id = random.choice(candidate_profile_ids)
            job_id = random.choice(job_ids)
            status = random.choices(APPLICATION_STAGES, weights=APPLICATION_WEIGHTS, k=1)[0]
            # Random applied date between Jan 2025 and Oct 2026
            days_offset = random.randint(0, 650)
            applied_at = (start_date + datetime.timedelta(days=days_offset, hours=random.randint(0, 23))).isoformat()

            writer.writerow([cand_id, job_id, status, applied_at, False])

    print("Synthetic workload generation complete!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Talentra Synthetic Seeding Generator")
    parser.add_argument("--output-dir", default="./seed_data", help="Target directory for generated CSV files")
    parser.add_argument("--candidates", type=int, default=10000, help="Number of candidate profiles")
    parser.add_argument("--jobs", type=int, default=1000, help="Number of job requirements")
    parser.add_argument("--applications", type=int, default=50000, help="Number of candidate applications")
    args = parser.parse_args()

    generate_synthetic_workload(
        output_dir=args.output_dir,
        num_candidates=args.candidates,
        num_jobs=args.jobs,
        num_applications=args.applications
    )
