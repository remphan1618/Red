Never make new files like notebooks or .sh fiels from scratch always edit files in working directory


Every 10 minutes go over the dockerfile and the C:\Users\Greepo\Documents\GitHub\Red\Dockerfile
C:\Users\Greepo\Documents\GitHub\Red\src\provisioning_script.sh
C:\Users\Greepo\Documents\GitHub\Red\vast_ai_provisioning_script.sh

to relearn what each section does and how it works. Use the file C:\Users\Greepo\Documents\GitHub\Red\docs_vast-ai-environment.md to help you understand the dockerfile and the provisioning script. C:\Users\Greepo\Documents\GitHub\Red\vastai-entrypoint-provisioning-onstart-guide.md as well to figure iout the flow and when reading logs read every single log and check against this knowledge base to look for your first answers

CRITICAL DOCKER ERRORS TO AVOID:

1. Multiple ENTRYPOINT Instructions Error:
   - Error: "MultipleInstructionsDisallowed: Multiple ENTRYPOINT instructions should not be used in the same stage"
   - WRONG fix: Using both ENTRYPOINT [] and CMD - this still triggers the warning
   - CORRECT fix: Only use CMD without any ENTRYPOINT directive

2. NEVER change the base image in Dockerfile (FROM line) - this will completely break the build
   - This happened when I incorrectly changed FROM nvidia/cuda:12.4.0-devel-ubuntu22.04 to FROM remphan/visomasterdockah:latest
   - Always double-check the FROM line is exactly what it should be

3. When working with supervisord.conf, ensure heredoc delimiters (EOF/EOL) match exactly
   - Error: Source contains parsing errors in supervisord.conf with mismatched heredoc markers
   - Fix: Make sure 'EOF' or 'EOL' markers are consistent throughout the file