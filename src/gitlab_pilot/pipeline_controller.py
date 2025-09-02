import logging
import time
import os

class PipelineController():
    def __init__(self, connection, project_id, branch_name):
        """
        Initialize the PipelineController with connection details, project ID, and branch name.
        """
        self.connection = connection
        self.project_id = project_id
        self.branch_name = branch_name
        logging.info(f"PipelineController initialized for project {self.project_id} on branch '{self.branch_name}'")
    
    def trigger_pipeline_job(self, variables):
        """
        Trigger a pipeline job for the specified branch with provided variables.
        """
        try:
            logging.info(f"Attempting to trigger pipeline for project {self.project_id} on branch '{self.branch_name}' with variables: {variables}")
            
            # Retrieve the project and trigger a new pipeline
            project = self.connection.projects.get(self.project_id)
            pipeline = project.pipelines.create({
                'ref': self.branch_name,
                'variables': [{'key': k, 'value': v} for k, v in variables.items()]
            })
            
            pipeline_id = pipeline.id
            logging.info(f"Pipeline triggered successfully with ID: {pipeline_id}")
            
            if pipeline_id:
                return pipeline_id
            
            return None
        
        except Exception as e:
            logging.error(f"Failed to trigger pipeline for project {self.project_id} on branch '{self.branch_name}': {e}")
            return None
        
    def monitor_pipeline_jobs(self, pipeline_id, interval=2):
        """
        Monitor the status of each job in the triggered pipeline until all jobs complete.
        """
        try:
            project = self.connection.projects.get(self.project_id)
            pipeline = project.pipelines.get(pipeline_id)
            logging.info(f"Monitoring all jobs in pipeline ID {pipeline_id} for completion...")

            # Dictionary to store final statuses of each job
            job_statuses = {}
            
            while True:
                all_jobs = pipeline.jobs.list(all=True)  # Retrieve all jobs in the pipeline
                completed_jobs = 0
                
                for job in all_jobs:
                    # Fetch the complete job object by ID to ensure full data access
                    full_job = project.jobs.get(job.id)
                    job_status = full_job.status
                    
                    # Display or log running status
                    if job_status not in ['success', 'failed', 'canceled', 'skipped']:
                        print(f"Job ID {full_job.id} is running with status: {job_status}")
                    else:
                        completed_jobs += 1
                        
                        artifact_name = None
                        try:
                            artifact_name = full_job.artifacts_file.get('filename')
                        except Exception as e:
                            logging.error(f"Job ID {full_job.id} has no artifact")
                        
                        job_statuses[full_job.id] = {'status': job_status, 'artifact': artifact_name}
                        logging.info(f"Job ID {full_job.id} completed with status: {job_status}")
                        
                    # Break the loop when all jobs are complete
                    if completed_jobs == len(all_jobs):
                        logging.info(f"All jobs in pipeline ID {pipeline_id} completed.")
                        return job_statuses
                    
                    # Wait for the specified interval before the next status check
                    time.sleep(interval)
                    print("Waiting for jobs to complete...")  # Additional feedback during waiting
        
        except Exception as e:
            logging.error(f"Failed to monitor jobs in pipeline ID {pipeline_id}: {e}")
            return None
        
    def download_artifacts(self, job_id, artifact_name, directory):
        """
        Download artifacts for jobs if available.
        """
        download_status = {}

        if not os.path.exists(directory):
            os.makedirs(directory)
            logging.info(f"Created directory for artifacts: {directory}")

        project = self.connection.projects.get(self.project_id)

        if artifact_name:
            artifact_path = os.path.join(directory, artifact_name)
            job = project.jobs.get(job_id)

            try:
                # Check if the job has artifacts
                if not job.artifacts:
                    logging.warning(f"No artifacts found for Job ID {job_id}")
                    download_status[job_id] = False
                    return download_status

                # Attempt to stream the artifact file
                artifact_content  = job.artifacts()
                if artifact_content  is None:
                    logging.error(f"Failed to retrieve artifact stream for Job ID {job_id}")
                    download_status[job_id] = False
                    return download_status

                # Write the artifact content
                with open(artifact_path, 'wb') as f:
                    f.write(artifact_content )

                download_status[job_id] = True
                logging.info(f"Downloaded artifact '{artifact_name}' for Job ID {job_id} to {artifact_path}")
            except Exception as e:
                download_status[job_id] = False
                logging.error(f"Failed to download artifact for Job ID {job_id}: {e}")
  
        else:
            download_status[job_id] = False
            logging.info(f"No artifact specified for Job ID {job_id}")

        return download_status
        
        