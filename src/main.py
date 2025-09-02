import logging
import sys
import os
from rich.progress import Progress
from rich.console import Console
import time
import config 
from threading import Thread
from pipeline_handler import PipelineHandler
from gitlab_pilot import project_to_job_mapper

# Set up logging configuration to log INFO and higher levels to both console and a file
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),                       # Log to console
        logging.FileHandler('main.log', mode='w')      # 'w' mode to overwrite file on each run
    ]
)

logger = logging.getLogger(__name__)

# Add the 'src' directory to Python's module search path
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

def main():
    """
    Main function to handle GitLab connection, group/subgroup fetching, and project validation.
    """
    console = Console()
    
    console.print("[bold red]======================= GITLAB Pipeline Manager =======================[/bold red]")
    pipeline_handler = PipelineHandler(base_url=config.BASE_URL, private_token=config.PRIVATE_TOKEN)
    
    user_name, user_id = pipeline_handler.get_user_info()
    console.print(f"[bold green]Welcome {user_name}, UserId: {user_id}[/bold green]")
    
    pipeline_handler.initialize_user_id(user_id=user_id)    
    
    all_projects = {}
    
    def fetch_projects():
        nonlocal all_projects
        all_projects = pipeline_handler.get_projects(sub_group_id=None)   
    
    project_thread = Thread(target=fetch_projects)
    project_thread.start()
    
    with Progress() as progress:
        task = progress.add_task("[cyan]Fetching Projects...",total=100)

        while project_thread.is_alive():
            project_thread.join(timeout=0.1)
            progress.update(task, advance=1)
            time.sleep(0.1)
            if progress.tasks[0].completed >= 100:
                progress.update(task, completed=0)  # Reset to simulate continuous progress
            
        progress.update(task, completed=100)
        
    try:
        while True:
            # Simulating user selection of a client
            client_list = ['BGT', 'STM', 'PGMC', 'COLLABORATIVE_PROJECTS', 'PERSONAL_PROJECTS','ALLOTHERS'] 
            selected_client = pipeline_handler.show_options(
                selection_list=client_list, 
                txt='project',
                display_horizontal=True
            ).lower()
            
            if not selected_client:
                console.print("[red]Invalid selection. Please try again.[/red]")
                continue # Return to the client selection if invalid input
            
            if selected_client == 'menu':
                console.print("[red]Returning to projects selection.[/red]")
                continue
            
            selected_project = pipeline_handler.show_options(
                selection_list=all_projects[selected_client], 
                txt='sub-project', 
                display_horizontal=False
            )

            if not selected_project:
                console.print("[red]Invalid selection. Please try again.[/red]")
                continue # Return to the client selection if invalid input
            
            if selected_project == 'menu':
                console.print("[red]Returning to projects selection.[/red]")
                continue
            
            selected_project_id = selected_project['id']
            
            pipeline_handler.initialize_project_id(project_id=selected_project_id)
            branch_names = pipeline_handler.get_branches()
            
            if not branch_names:
                raise ValueError(f"No branches for the project {selected_project['name']}'exist.")
            
            selected_branch_name = pipeline_handler.show_options(
                selection_list=branch_names, 
                txt='branch', 
                display_horizontal=False
            )
            
            if not selected_branch_name:
                console.print("[red]Invalid selection. Please try again.[/red]")
                continue # Return to the client selection if invalid input
            
            if selected_branch_name == 'menu':
                console.print("[red]Returning to projects selection.[/red]")
                continue
            
            pipeline_handler.initialize_branch_name(branch_name=selected_branch_name)
            yml_file_content = pipeline_handler.get_file_from_repo(file_path=".gitlab-ci.yml")

            if not yml_file_content:
                raise FileNotFoundError(f"No .gitlab-ci.yml file found on branch {selected_branch_name}.")
            
            job_stages = pipeline_handler.get_job_stages()

            if not job_stages:
                raise ValueError(f"No stages for project {selected_project['name']} on brnach {selected_branch_name}")
            
            stages_with_all = job_stages + ['all_jobs']
            
            selected_stage = pipeline_handler.show_options(
                selection_list=stages_with_all,
                txt='pipeline job stage',
                display_horizontal=True
            )
            
            if not selected_stage:
                console.print("[red]Invalid selection. Please try again.[/red]")
                continue # Return to the client selection if invalid input
            
            if selected_stage == 'menu':
                print("Returning to projects selection.")
                continue
            
            stages = [selected_stage] if selected_stage != 'all_jobs' else job_stages
            console.print(f"[bold magenta]Initiating job(s): {', '.join(stages)}[/bold magenta]")
                
            pipeline_handler.initialize_pipeline_controller()
            
            for stage in stages:
                pipeline_handler.initialize_stage_name_and_variable_handler(stage_name=stage)
                job_variables = pipeline_handler.get_job_variables()
                
                variables = {}
                if job_variables:
                    if isinstance(job_variables, list):
                        variables = {'TRIGGER_TARGET': stage}
                        console.print(f"[bold magenta]The job '{selected_stage}' accepts the following variables:[/bold magenta]")
                        for var_name in job_variables:
                            var_value = console.input(f"[bold magenta]Enter the value for {var_name}(optional): [bold magenta]").strip()
                            variables[var_name] = var_value 
                    else:
                        variables = job_variables
                        
                pipeline_id = pipeline_handler.trigger_job(variables=variables)
                
                if not pipeline_id:
                    raise ValueError(f"Failed to trigger pipeline")
                
                job_stauses = pipeline_handler.monitor_jobs(pipeline_id=pipeline_id, interval=2)
                
                if not job_stauses:
                    raise ValueError(f"Failes to get job status")
                
                for job_id, job_info in job_stauses.items():
                    
                    job_status = job_info['status']
                    job_artifact = job_info['artifact']
                    
                    if job_status == "success" and job_artifact:
                        download_artifact = input("Download artifact(s)? (y/n): ").strip().lower()
                        if download_artifact == 'y':
                            
                            download_status = pipeline_handler.download_artifact(
                                job_id=job_id,
                                artifact_name=f"{job_artifact}",
                                directory="./downloads"
                            )
                            
                            if download_status[job_id]:
                                print("Downloaded Successfully!!")
                                continue
                    else:
                        print(f"No Artifat to download! Job status:{job_status}")
    
    except ValueError as ve:
        console.print(f"[bold red]Invalid Value Exception: {ve}[/bold red]")
    except Exception as e:
        console.print(f"[bold red]Unknown Exception: {e}[/bold red]")
        
                        

if __name__ == '__main__':
    main()