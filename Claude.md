# Claude Development Guidelines

This document outlines the development standards and requirements for the FSP Lightreach PO Manager project.

## ⚠️ IMPORTANT: Deployment Workflow

**NEVER push directly to main/master or deploy directly to Heroku.**

Always follow this workflow:
1. Create a feature branch for your changes
2. Make commits on the feature branch
3. Create a Pull Request for review
4. Wait for CI checks to pass and PR approval
5. Merge the PR (deployment happens automatically)

```bash
# CORRECT workflow
git checkout -b feature/my-feature
# make changes...
git add <files>
git commit -m "My changes"
git push origin feature/my-feature
# Then create PR via GitHub

# WRONG - Never do this!
git push origin main          # ❌ Don't push directly to main
git push heroku main          # ❌ Don't deploy directly to Heroku
```

## Pre-PR Checklist

Before creating a Pull Request, ensure the following requirements are met:

### 1. Testing Requirements
- **RSpec Coverage**: Maintain at least **70% test coverage**
  - Run: `bundle exec rspec`
  - Check coverage: Coverage report is generated in `coverage/index.html`
  - Coverage threshold is enforced in CI/CD pipeline

### 2. Code Quality
- **Passing Tests**: All RSpec tests must pass
  - Run: `bundle exec rspec`
  - No failing tests allowed

- **Rubocop Linting**: Code must pass Rubocop style checks
  - Run: `bundle exec rubocop`
  - Auto-fix issues: `bundle exec rubocop -A`
  - Zero offenses required

### 3. Security
- **Brakeman Security Scan**: Address all high and medium severity warnings
  - Run: `bin/brakeman --no-pager`
  - Review and fix security vulnerabilities
  - Document any intentional exceptions in `config/brakeman.ignore`

## Development Workflow

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write tests for new functionality
   - Update existing tests as needed
   - Follow Rails and Ruby best practices

3. **Run the quality checks**
   ```bash
   # Auto-fix linting issues
   bundle exec rubocop -A

   # Run tests with coverage
   bundle exec rspec

   # Check security
   bin/brakeman --no-pager
   ```

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "Your descriptive commit message"
   ```

5. **Create Pull Request**
   - Ensure all checks pass (tests, coverage, rubocop, brakeman)
   - Add descriptive PR title and description
   - Link to relevant issues

## Continuous Integration

The GitHub Actions CI pipeline runs on all PRs and includes:
- RSpec test suite with coverage reporting
- Rubocop linting
- Brakeman security scanning
- Coverage threshold enforcement (70%)

**All checks must pass before merging.**

## Code Standards

- Follow Rails conventions
- Use double-quoted strings (enforced by Rubocop)
- Keep methods focused and concise
- Write descriptive commit messages
- Add comments for complex logic
- Update documentation when changing behavior

## Testing Standards

- Write tests for all new features
- Update tests when modifying existing features
- Use descriptive test names
- Follow RSpec best practices
- Aim for meaningful coverage, not just percentage

## Security Standards

- Never bypass SSL verification in production code
- Validate user inputs
- Use parameterized queries (avoid SQL injection)
- Follow OWASP best practices
- Review Brakeman warnings before merging
