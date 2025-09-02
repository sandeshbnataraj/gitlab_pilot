# **GitLab Pilot 🚀**  
*A streamlined tool to automate GitLab CI/CD pipeline management*  

## **Overview**  
**GitLab Pilot** is a Python-based application designed to **simplify CI/CD pipeline management** in GitLab. It provides an intuitive way to **trigger, monitor, and manage pipelines** without manually navigating the GitLab UI. This tool helps teams streamline their workflow by centralizing pipeline execution, artifact handling, and variable management.  

## **Features**  
✅ **Trigger GitLab pipelines** without logging into GitLab.  
✅ **Manage CI/CD pipeline variables** dynamically.  
✅ **Download artifacts** directly from completed pipelines.  
✅ **Automate versioning and tagging** for structured releases.  
✅ **Enhance pipeline execution across multiple projects.**  

## **Project Repository**  
🔗 **GitLab Repository:** [GitLab Pilot - Develop](https://gitlab.ilts.com/snataraj/gitlab_pilot/-/tree/develop?ref_type=heads)  

---

## **Installation & Setup**  

### **1. Clone the Repository**  
```sh
git clone https://gitlab.ilts.com/snataraj/gitlab_pilot.git
cd gitlab_pilot
```

### **2. Install Poetry (If Not Installed)**  
```sh
pip install poetry
```

### **3. Install Dependencies with Poetry**  
```sh
poetry install
```

### **4. Configure Environment Variables**  
Create a `.env` file in the project root and add your GitLab credentials:  
```
GITLAB_BASE_URL=https://gitlab.ilts.com
GITLAB_PRIVATE_TOKEN=your_private_token
```
> **🔹 Note:** Generate your **GitLab Private Token** from `Settings > Access Tokens` with `api`, `read_repository`, and `write_repository` scopes.

### **5. Activate the Virtual Environment**  
Run the following command to enter the Poetry-managed virtual environment:  
```sh
poetry shell
```

---

## **Usage Guide**  

### **1. Trigger a Pipeline**  
Run the following command to **start a pipeline**:  
```sh
poetry run python main.py trigger --project_id <project_id> --branch <branch_name>
```
> **Example:**  
```sh
poetry run python main.py trigger --project_id 12345 --branch develop
```

### **2. Fetch Pipeline Logs**  
Retrieve logs of a specific pipeline:  
```sh
poetry run python main.py logs --pipeline_id <pipeline_id>
```
> **Example:**  
```sh
poetry run python main.py logs --pipeline_id 67890
```

### **3. Download Artifacts**  
Download build artifacts from a completed pipeline:  
```sh
poetry run python main.py artifacts --pipeline_id <pipeline_id> --output_dir ./artifacts
```
> **Example:**  
```sh
poetry run python main.py artifacts --pipeline_id 67890 --output_dir ./artifacts
```

### **4. View Available Variables**  
To list available variables in a pipeline:  
```sh
poetry run python main.py variables --project_id <project_id>
```

### **5. Tag & Version Management**  
To **create a new Git tag** for versioning:  
```sh
poetry run python main.py tag --project_id <project_id> --tag_name v1.0.0
```

---

## **Running Tests**  
To run the test suite, use:  
```sh
poetry run pytest
```

---

## **Future Enhancements**  
🚀 **Kubernetes integration** for deployment automation  
🚀 **Slack notifications** for real-time pipeline updates  
🚀 **Enhanced logging & error handling** for better debugging  

---

## **Contributing**  
🙌 **Contributions are welcome!** If you'd like to improve GitLab Pilot:  
1. **Fork the repository**  
2. **Create a feature branch** (`git checkout -b feature-name`)  
3. **Commit changes** (`git commit -m "Added new feature"`)  
4. **Push to GitLab** (`git push origin feature-name`)  
5. **Open a Merge Request** 🚀  

---

## **Maintainer & Contact**  
👤 **Maintainer:** Sandesh Nataraj  
📧 Email: [your-email@example.com]  
🔗 **GitLab Repo:** [GitLab Pilot - Develop](https://gitlab.ilts.com/snataraj/gitlab_pilot/-/tree/develop?ref_type=heads)  

---

This `README.md` **accurately reflects your use of Poetry**, includes **clear installation & usage steps**, and is structured for easy readability. 🚀 Let me know if you’d like any refinements!