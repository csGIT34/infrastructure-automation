from setuptools import setup, find_packages

setup(
    name="infra-cli",
    version="1.0.0",
    description="Infrastructure Self-Service CLI",
    author="Platform Engineering Team",
    python_requires=">=3.9",
    py_modules=["infra_cli"],
    install_requires=[
        "click>=8.0.0",
        "requests>=2.28.0",
        "pyyaml>=6.0",
    ],
    entry_points={
        "console_scripts": [
            "infra=infra_cli:cli",
        ],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
)
