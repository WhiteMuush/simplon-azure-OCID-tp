run:
	@if docker run -p 8080:8080 -d --name python-app python-app:latest > /dev/null ; then \
		echo "Python App Run Correctly"; \
	else \
		echo "Error, something wrong"; \
	fi

build:
	@if docker build -t python-app:latest . > /dev/null ; then \
		echo "Python App Build Correctly"; \
	else \
		echo "Error, something wrong"; \
	fi

restart:
	@if docker restart python-app > /dev/null ; then \
		echo "Python App restart Correctly"; \
	else \
		echo "Error, something wrong"; \
	fi

kill:
	@docker stop python-app > /dev/null
	@if docker rm python-app -v > /dev/null ; then \
		echo "Python App Kill Correctly"; \
	else \
		echo "Error, something wrong"; \
	fi