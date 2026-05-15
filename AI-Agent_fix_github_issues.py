import os
import requests
import time
import subprocess
from dotenv import load_dotenv

# Load GITHUB_TOKEN from .env file
load_dotenv()

# Configuration
REPOS = [
    "pioneerAlpha/conversion-automation-python"
]
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN")
HEADERS = {"Authorization": f"token {GITHUB_TOKEN}"}
MODEL = "ollama/deepseek-coder-v2"
CONFIG_FILE = "ollama_config.yaml"


def get_open_issues(repo_name):
    """Fetches open issues with the 'ai-fix' label."""
    url = f"https://api.github.com/repos/{repo_name}/issues?state=open&labels=ai-fix"
    try:
        response = requests.get(url, headers=HEADERS)
        if response.status_code == 200:
            return response.json()
        elif response.status_code == 401:
            print("Error: Unauthorized. Check your GITHUB_TOKEN in .env")
        else:
            print(
                f"Error fetching issues from {repo_name}: {response.status_code}")
    except Exception as e:
        print(f"Network error: {e}")
    return []


def run_agent(issue_url):
    """
    Triggers SWE-agent. Returns True if the agent exits successfully.
    """
    print(f"\n" + "="*60)
    print(f"STARTING AI AGENT FOR: {issue_url}")
    print("="*60 + "\n")

    # Constructing the command using the 'sweagent' CLI
    command = [
        "sweagent", "run",
        "--model_name", MODEL,
        "--config_file", CONFIG_FILE,
        "--issue_url", issue_url
    ]

    try:
        # Using subprocess.run to keep the output visible in your terminal
        result = subprocess.run(command, check=False)
        return result.returncode == 0
    except FileNotFoundError:
        print("Error: 'sweagent' command not found. Ensure your virtual environment is active.")
        return False


def remove_label(repo_name, issue_number):
    """Removes the 'ai-fix' label so the agent doesn't loop on the same issue."""
    url = f"https://api.github.com/repos/{repo_name}/issues/{issue_number}/labels/ai-fix"
    response = requests.delete(url, headers=HEADERS)
    if response.status_code in [200, 204]:
        print(
            f"Successfully removed 'ai-fix' label from {repo_name} #{issue_number}")
    else:
        print(f"Failed to remove label: {response.status_code}")


def main():
    if not GITHUB_TOKEN:
        print("CRITICAL ERROR: GITHUB_TOKEN not found in environment or .env file.")
        return

    print(f"Monitoring {len(REPOS)} repositories...")

    while True:
        for repo in REPOS:
            print(f"Checking {repo}...")
            issues = get_open_issues(repo)
            print('Total issues:', len(issues))
            for issue in issues:
                issue_url = issue['html_url']
                issue_number = issue['number']
                print('issue_number:', issue_url)
                print('issue_url:', issue_url)

                # We only remove the label if the agent actually finishes its run
                success = run_agent(issue_url)

                if success:
                    remove_label(repo, issue_number)
                else:
                    print(
                        f"\n[!] Agent failed or was interrupted for {issue_url}.")
                    print("Label 'ai-fix' remains for manual retry.\n")

        print("Check complete. Sleeping for 5 minutes...")
        time.sleep(300)


if __name__ == "__main__":
    main()
