# Contributing to LuCI Mobile

Thank you for your interest in contributing to LuCI Mobile! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Pull Request Process](#pull-request-process)
- [Issue Reporting](#issue-reporting)
- [Feature Requests](#feature-requests)
- [Testing](#testing)
- [Documentation](#documentation)

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please be respectful and inclusive in all interactions.

## Getting Started

### Prerequisites

- Flutter SDK (version 3.8.1 or higher)
- Dart SDK
- Git
- An IDE (VS Code, Android Studio, or IntelliJ IDEA)
- OpenWrt router for testing (optional but recommended)

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/cogwheel0/luci-mobile.git
   cd luci-mobile
   ```
3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/cogwheel0/luci-mobile.git
   ```

## Development Setup

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Run the App

```bash
flutter run
```

### 3. Set Up Your Development Environment

- Install Flutter and Dart extensions in your IDE
- Configure your IDE for Dart/Flutter development
- Set up a code formatter (dart format)

### 4. Testing Environment

For testing with a real router:
- Set up an OpenWrt router with LuCI web interface
- Configure network access to the router
- Note the router's IP address for testing

## Coding Standards

### Dart/Flutter Standards

- Follow the [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Use `flutter analyze` to check for issues
- Format code using `dart format`
- Follow Flutter best practices and conventions

### Code Organization

- Keep files focused and single-purpose
- Use meaningful file and class names
- Group related functionality together
- Follow the existing project structure

### Naming Conventions

- **Files**: Use snake_case (e.g., `api_service.dart`)
- **Classes**: Use PascalCase (e.g., `NetworkInterface`)
- **Variables**: Use camelCase (e.g., `ipAddress`)
- **Constants**: Use camelCase (e.g., `maxRetryCount`). `constant_identifier_names`
  is enabled, and CI runs `flutter analyze --fatal-infos`, so SCREAMING_SNAKE_CASE
  fails the build.

### Documentation

- Add comments for complex logic
- Document public APIs and methods
- Update README.md for significant changes
- Include examples for new features

## Pull Request Process

### 1. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Your Changes

- Write clean, well-documented code
- Follow the coding standards
- Add tests for new functionality
- Update documentation as needed

### 3. Test Your Changes

```bash
# Run tests
flutter test

# Analyze code
flutter analyze

# Format code
dart format .

# Build for different platforms
flutter build apk
flutter build ios
```

### 4. Commit Your Changes

Use conventional commit messages:

```bash
git commit -m "feat: add new dashboard widget"
git commit -m "fix: resolve authentication timeout issue"
git commit -m "docs: update API documentation"
```

### 5. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub with:

- **Clear title** describing the change
- **Detailed description** of what was changed and why
- **Screenshots** for UI changes
- **Test instructions** for reviewers
- **Related issues** if applicable

### 6. Pull Request Guidelines

- Keep PRs focused and small
- Respond to review comments promptly
- Update PR based on feedback
- Ensure all CI checks pass

## Issue Reporting

### Before Reporting

1. Check existing issues for duplicates
2. Search the documentation
3. Try to reproduce the issue

### Issue Template

When creating an issue, include:

- **Clear title** describing the problem
- **Detailed description** of the issue
- **Steps to reproduce**
- **Expected vs actual behavior**
- **Environment details** (OS, Flutter version, device)
- **Screenshots** if applicable
- **Logs** if available

### Bug Reports

For bug reports, include:

- Flutter version: `flutter --version`
- Device/emulator details
- Steps to reproduce
- Error messages and stack traces
- Router configuration details

### Feature Requests

For feature requests, include:

- Clear description of the feature
- Use cases and benefits
- Mockups or examples if applicable
- Priority level

## Feature Requests

### Guidelines

- Check if the feature already exists
- Consider the impact on existing functionality
- Think about backward compatibility
- Consider the scope and complexity

### Submitting Feature Requests

1. Use the feature request template
2. Provide clear use cases
3. Include mockups or examples
4. Consider implementation complexity

## Testing

### Unit Tests

- Write tests for new functionality
- Maintain good test coverage
- Use meaningful test names
- Mock external dependencies

### Integration Tests

- Test API communication
- Test authentication flows
- Test error handling
- Test different network conditions

### Manual Testing

- Test on different devices
- Test with different router configurations
- Test error scenarios
- Test performance

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/widget_test.dart

# Run with coverage
flutter test --coverage
```

## Documentation

### Code Documentation

- Document public APIs
- Add inline comments for complex logic
- Update method documentation when changing signatures
- Include examples for complex methods

### User Documentation

- Update README.md for new features
- Add usage examples
- Include troubleshooting guides
- Keep screenshots up to date

### API Documentation

- Document API endpoints
- Include request/response examples
- Document error codes
- Keep API documentation current

## Review Process

### Code Review Guidelines

- Be constructive and respectful
- Focus on code quality and functionality
- Consider security implications
- Check for performance issues
- Verify documentation updates

### Review Checklist

- [ ] Code follows style guidelines
- [ ] Tests are included and pass
- [ ] Documentation is updated
- [ ] No security vulnerabilities
- [ ] Performance is acceptable
- [ ] Backward compatibility maintained

## Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Checklist

- [ ] All tests pass
- [ ] Documentation is updated
- [ ] Changelog is updated
- [ ] Version is bumped
- [ ] Release notes are prepared

## Getting Help

### Questions and Support

- Check the documentation first
- Search existing issues
- Ask questions in discussions
- Join our community channels

### Mentorship

New contributors are welcome! We're happy to:

- Help you get started
- Review your first PR
- Provide guidance on complex features
- Answer questions about the codebase

## Recognition

Contributors will be recognized in:

- Project README
- Release notes
- Contributor hall of fame
- GitHub contributors page

Thank you for contributing to LuCI Mobile! Your contributions help make this project better for everyone. 