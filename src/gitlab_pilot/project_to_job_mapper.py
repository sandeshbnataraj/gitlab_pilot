import config, logging
from gitlab_pilot import StageFunctionRegistry

logger = logging.getLogger(__name__)

def create_deferred_function(project_id, stage_name):
    # This deferred function retrieves the actual function at runtime
    def deferred_func(variables_handler):
        func_name = f"get_var_{project_id}_{stage_name}"

        # Attempt to retrieve the actual function from variables_handler
        func = getattr(variables_handler, func_name, None)
            
        # Log whether the function was found or not
        if func:
            logger.info(f"function found in VariablesManager for project_id={project_id} and stage_name={stage_name}")
            return func
        else:
            logger.error(f"No function found in VariablesManager for project_id={project_id} and stage_name={stage_name}")
            return None

    return deferred_func    # Return the deferred function

for mapping in config.PROJECTS_JOB_MAPPING:
    for project_id, stages in mapping.items():
        for stage_name in stages:
            # Create the deferred function for the specific project and stage
            register_func = create_deferred_function(project_id=project_id, stage_name=stage_name)
            # Register the deferred function in StageFunctionRegistry
            StageFunctionRegistry.register_function(project_id=project_id ,stage_name=stage_name)(register_func)
                    

