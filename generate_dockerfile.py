import ollama

PROMPT="""
Only Generate an ideal 	Dockerfile for {language} with best practices. Do not provide any description
Include:
- Base image
- Installing dependencies
- Setting working directory
- Adding source code
- Running the application
- Multistage dockerfile 
"""

def generate_dockerfile(language):
	response= ollama.chat(model= 'llama3.2', messages=[{'role': 'user', 'content': PROMPT.format(language=language)}])
	return response['message']['content']


if __name__ == '__main__':
	language= input("Enter your programming language: ")
	dockerfile = generate_dockerfile(language)
	print("\n Generated Dockerfile for", language, ":\n")
	print(dockerfile) 
