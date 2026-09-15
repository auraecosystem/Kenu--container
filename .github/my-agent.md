The **Kenu container** (`Kenu--container`) is a specialized containerization and deployment architecture developed under the `auraecosystem` organization. It is engineered to act as a secure, production-grade container layer for managing sovereign node infrastructure, ensuring that distributed nodes and local services run reliably inside isolated, optimized environments.

Key aspects of the Kenu container architecture include:

* **Sovereign Node Isolation:** Built using hardened multi-stage builds (such as CUDA-accelerated base images with non-root runtime users) to maintain security and prevent unauthorized host access.
* **Infrastructure Orchestration:** Designed to integrate seamlessly with tools like Docker Compose, custom JSON configuration schemas, and automated CI/CD pipelines to manage stateful data and multi-service deployments.
* **Ecosystem Integration:** Functions as part of the broader Web4 and decentralized protocol tooling maintained across the Aura Ecosystem and Qubuhub.

# Create a task from an inline description
$ gh agent-task create "build me a new app"

# Create a task from an inline description and follow logs
$ gh agent-task create "build me a new app" --follow

# Create a task from a file
$ gh agent-task create -F task-desc.md

# Create a task with problem statement from stdin
$ echo "build me a new app" | gh agent-task create -F -

# Create a task with an editor
$ gh agent-task create

# Create a task with an editor and a file as a template
$ gh agent-task create -F task-desc.md

# Select a different base branch for the PR
$ gh agent-task create "fix errors" --base branch

# Create a task using the custom agent defined in '.github/agents/my-agent.md'
$ gh agent-task create "build me a new app" --custom-agent my-agent
# List releases in the current repository
$ gh api repos/{owner}/{repo}/releases

# Post an issue comment
$ gh api repos/{owner}/{repo}/issues/123/comments -f body='Hi from CLI'

# Post nested parameter read from a file
$ gh api gists -F 'files[myfile.txt][content]=@myfile.txt'

# Add parameters to a GET request
$ gh api -X GET search/issues -f q='repo:cli/cli is:open remote'

# Use a JSON file as request body
$ gh api repos/{owner}/{repo}/rulesets --input file.json

# Set a custom HTTP header
$ gh api -H 'Accept: application/vnd.github.v3.raw+json' ...

# Opt into GitHub API previews
$ gh api --preview baptiste,nebula ...

# Print only specific fields from the response
$ gh api repos/{owner}/{repo}/issues --jq '.[].title'

# Use a template for the output
$ gh api repos/{owner}/{repo}/issues --template \
  '{{range .}}{{.title}} ({{.labels | pluck "name" | join ", " | color "yellow"}}){{"\n"}}{{end}}'

# Update allowed values of the "environment" custom property in a deeply nested array
$ gh api -X PATCH /orgs/{org}/properties/schema \
   -F 'properties[][property_name]=environment' \
   -F 'properties[][default_value]=production' \
   -F 'properties[][allowed_values][]=staging' \
   -F 'properties[][allowed_values][]=production'

# List releases with GraphQL
$ gh api graphql -F owner='{owner}' -F name='{repo}' -f query='
  query($name: String!, $owner: String!) {
    repository(owner: $owner, name: $name) {
      releases(last: 3) {
        nodes { tagName }
      }
    }
  }
'

# List all repositories for a user
$ gh api graphql --paginate -f query='
  query($endCursor: String) {
    viewer {
      repositories(first: 100, after: $endCursor) {
        nodes { nameWithOwner }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
'

# Get the percentage of forks for the current user
$ gh api graphql --paginate --slurp -f query='
  query($endCursor: String) {
    viewer {
      repositories(first: 100, after: $endCursor) {
        nodes { isFork }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
' | jq 'def count(e): reduce e as $_ (0;.+1);
[.[].data.viewer.repositories.nodes[]]
