import logging
from rich.console import Console

class StageFunctionRegistry:
    function_map = {}
    
    @classmethod
    def register_function(cls, project_id, stage_name):
        """
        Class method to register a function for a given project_id and stage_name combination.
        """
        def wrapper(func):
            cls.function_map[(project_id, stage_name)] = func
    
            logging.info(f"Registerd the func: {func}")
            return func
        return wrapper
    
    # Decorator to choose and call the right function based on dynamically passed id and stage_name
    @classmethod
    def dynamic_call(cls, original_method):
        """
        Decorator to choose and call the mapped function for a project_id and stage_name, if available.
        """
        def wrapper(self, *args, **kwargs):
            variables_handler = self.variables_handler
            key = (self.project_id, self.stage_name)
            #kwargs.update({'stage_name': stage_name, 'branch_name': branch_name, 'gitlab_manager': gitlab_manager})

            if key in cls.function_map:
                print(f"Executing function for project_id={self.project_id} and stage_name={self.stage_name}.")
                actual_func_from_deferred = cls.function_map[key](variables_handler)
                return actual_func_from_deferred(*args, **kwargs)
            else:
                print(f"No function found for project_id={self.project_id} and stage_name={self.stage_name}. Executing default method.")
                return original_method(self, *args, **kwargs) #original_method(self, project_id, stage_name, file_content, gitlab_manager, *args, **kwargs)
        return wrapper
