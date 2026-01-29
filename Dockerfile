#=== build stage === 
FROM eclipse-temurin:17-jdk AS build

WORKDIR /workspace

#파일 : . / 폴더 : 이름명시
COPY gradlew .
COPY gradle gradle
COPY build.gradle .
COPY settings.gradle .

RUN chmod +x gradlew
#(스프링은 자동으로해줌) 빌드 도중 라이브러리 없어서 다운로드 하지 않게 하기 위함.
RUN ./gradlew dependencies --no-daemon


#실제로는 GithubAction, Jenkins에서 테스트 진행하므로 생략
#=== test stage === 
FROM build AS test

WORKDIR /workspace
COPY src src

#테스트
#RUN ./gradlew test --no-daemon

# ./gradlew clean build 대신 사용 (소스변경시, 빌드폴더는 새로만들어지므로 무의미)
RUN ./gradlew bootJar --no-daemon


#=== run stage ===
FROM eclipse-temurin:17-jdk

WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["java", "-jar"]
CMD ["commerce.jar"]

#build.gradle -> jar {enabled = false} 로, jar 하나만 생성됨
COPY --from=test /workspace/build/libs/*.jar /app/commerce.jar
