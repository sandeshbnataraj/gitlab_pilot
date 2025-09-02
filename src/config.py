import os
from dotenv import load_dotenv
 
# Load environment variables from a .env file if present
load_dotenv()

BASE_URL = "https://gitlab.ilts.com"

# Read the private token from an environment variable
PRIVATE_TOKEN = os.getenv("PRIVATE_TOKEN")

# If PRIVATE_TOKEN is not set, prompt the user to input it
if not PRIVATE_TOKEN:
    PRIVATE_TOKEN = input("Please enter your private token: ")
    
# Ensure the token is not empty
if not PRIVATE_TOKEN:
    raise ValueError("A private token must be provided.")


PROJECTS_JOB_MAPPING = [
    { 84: ['create_db_release','update_version']},
    {73: ['create_db_release','update_version']}
]